// Supabase Edge Function: leave-ics
// Generates an ICS (iCalendar) feed for leave entries.
// Usage: GET /functions/v1/leave-ics?token=<ical_token>

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve(async (req: Request) => {
  try {
    const url = new URL(req.url);
    const token = url.searchParams.get("token");

    if (!token) {
      return new Response("Missing token parameter", { status: 400 });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Look up the profile by ical_token
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("*")
      .eq("ical_token", token)
      .single();

    if (profileError || !profile) {
      return new Response("Invalid token", { status: 401 });
    }

    // Fetch all non-deleted entries for this user
    const { data: entries, error: entriesError } = await supabase
      .from("leave_entries")
      .select("*")
      .eq("user_id", profile.id)
      .is("deleted_at", null)
      .order("date", { ascending: true });

    if (entriesError) {
      return new Response("Error fetching entries", { status: 500 });
    }

    // Generate ICS
    const ics = generateICS(entries ?? [], profile);

    return new Response(ics, {
      status: 200,
      headers: {
        "Content-Type": "text/calendar; charset=utf-8",
        "Content-Disposition": 'inline; filename="leave-ledger.ics"',
        "Cache-Control": "no-cache, no-store, must-revalidate",
      },
    });
  } catch (err) {
    return new Response(`Internal error: ${err.message}`, { status: 500 });
  }
});

interface LeaveEntry {
  id: string;
  date: string;
  leave_type: string;
  action: string;
  hours: number;
  adjustment_sign: string | null;
  notes: string | null;
}

interface Profile {
  id: string;
  anchor_payday: string;
  vac_accrual_rate: number;
  sick_accrual_rate: number;
}

function generateICS(entries: LeaveEntry[], profile: Profile): string {
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//LeaveLedger//LeaveLedger//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:Leave Ledger",
    "X-WR-TIMEZONE:America/New_York",
  ];

  // Add entry events
  for (const entry of entries) {
    const dateStr = entry.date.replace(/-/g, "");
    const nextDate = addDays(entry.date, 1).replace(/-/g, "");

    let title: string;
    switch (entry.action) {
      case "accrued":
        title = `${capitalize(entry.leave_type)} Accrued ${entry.hours.toFixed(2)}h`;
        break;
      case "used":
        title = `${capitalize(entry.leave_type)} Used ${entry.hours.toFixed(2)}h`;
        break;
      case "adjustment": {
        const sign = entry.adjustment_sign === "negative" ? "-" : "+";
        title = `${capitalize(entry.leave_type)} Adj ${sign}${entry.hours.toFixed(2)}h`;
        break;
      }
      default:
        title = `${capitalize(entry.leave_type)} ${entry.hours.toFixed(2)}h`;
    }

    const payPeriod = getPayPeriodDescription(entry.date, profile.anchor_payday);
    const isPosted = isEntryPosted(entry.date, profile.anchor_payday);

    const description = [
      entry.notes || "",
      `Pay Period: ${payPeriod}`,
      `Status: ${isPosted ? "Posted" : "Pending"}`,
      `leaveLedger://entry/${entry.id}`,
    ].join("\\n");

    const category = entry.action === "used" ? "Red" :
      entry.action === "accrued" ? "Green" :
      entry.adjustment_sign === "negative" ? "Red" : "Green";

    lines.push(
      "BEGIN:VEVENT",
      `UID:${entry.id}@leaveLedger`,
      `DTSTART;VALUE=DATE:${dateStr}`,
      `DTEND;VALUE=DATE:${nextDate}`,
      `SUMMARY:${title}`,
      `DESCRIPTION:${description}`,
      `CATEGORIES:${category}`,
      "TRANSP:TRANSPARENT",
      "END:VEVENT"
    );
  }

  // Add payday events (1 year back and forward)
  const now = new Date();
  const from = new Date(now);
  from.setFullYear(from.getFullYear() - 1);
  const to = new Date(now);
  to.setFullYear(to.getFullYear() + 1);

  const paydays = getPaydays(
    from.toISOString().split("T")[0],
    to.toISOString().split("T")[0],
    profile.anchor_payday
  );

  for (const payday of paydays) {
    const dateStr = payday.replace(/-/g, "");
    const nextDate = addDays(payday, 1).replace(/-/g, "");

    lines.push(
      "BEGIN:VEVENT",
      `UID:payday-${dateStr}@leaveLedger`,
      `DTSTART;VALUE=DATE:${dateStr}`,
      `DTEND;VALUE=DATE:${nextDate}`,
      `SUMMARY:Payday (Vac +${profile.vac_accrual_rate.toFixed(2)}h, Sick +${profile.sick_accrual_rate.toFixed(2)}h)`,
      "CATEGORIES:Blue",
      "TRANSP:TRANSPARENT",
      "END:VEVENT"
    );
  }

  lines.push("END:VCALENDAR");
  return lines.join("\r\n");
}

// Helper functions

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(dateStr + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().split("T")[0];
}

function daysBetween(a: string, b: string): number {
  const da = new Date(a + "T00:00:00Z");
  const db = new Date(b + "T00:00:00Z");
  return Math.round((db.getTime() - da.getTime()) / (1000 * 60 * 60 * 24));
}

function getPaydays(from: string, to: string, anchor: string): string[] {
  const result: string[] = [];
  const fromDays = daysBetween(anchor, from);
  let startOffset = Math.ceil(fromDays / 14) * 14;
  if (startOffset < fromDays) startOffset += 14;

  let current = addDays(anchor, startOffset - (startOffset > fromDays ? 14 : 0));
  // Ensure we start at or after 'from'
  while (daysBetween(from, current) < 0) {
    current = addDays(current, 14);
  }

  while (daysBetween(current, to) >= 0) {
    result.push(current);
    current = addDays(current, 14);
  }
  return result;
}

function paydayFor(dateStr: string, anchor: string): string {
  // Pay period end = payday - 7, start = payday - 20
  // Find which pay period contains the date
  const diff = daysBetween(anchor, dateStr);
  // Anchor period: start = anchor-20, end = anchor-7
  const anchorStart = addDays(anchor, -20);
  const anchorEnd = addDays(anchor, -7);

  const startDiff = daysBetween(anchorStart, dateStr);
  if (startDiff >= 0 && startDiff < 14) return anchor;

  const periods = Math.floor(startDiff / 14);
  const candidate = addDays(anchor, periods * 14);
  const candidateStart = addDays(candidate, -20);
  const candidateEnd = addDays(candidate, -7);

  const d = daysBetween(candidateStart, dateStr);
  if (d >= 0 && d < 14) return candidate;
  return addDays(candidate, 14);
}

function getPayPeriodDescription(dateStr: string, anchor: string): string {
  const payday = paydayFor(dateStr, anchor);
  const end = addDays(payday, -7);
  const start = addDays(end, -13);
  return `${start} to ${end}`;
}

function isEntryPosted(dateStr: string, anchor: string): boolean {
  const payday = paydayFor(dateStr, anchor);
  const today = new Date().toISOString().split("T")[0];
  return daysBetween(payday, today) >= 0;
}
