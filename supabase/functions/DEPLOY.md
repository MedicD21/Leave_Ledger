# Deploying the Leave ICS Edge Function

## Prerequisites
1. Install Supabase CLI: `brew install supabase/tap/supabase`
2. Login to Supabase: `supabase login`

## Deploy the Function

1. **Link your project** (if not already linked):
   ```bash
   cd /Users/dustinschaaf/Desktop/Leave_Ledger
   supabase link --project-ref wnlujkxyknbwergmetab
   ```

2. **Deploy the edge function**:
   ```bash
   supabase functions deploy leave-ics
   ```

   **Note:** `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are automatically provided by Supabase to Edge Functions - you don't need to set them manually.

## Test the Function

After deploying, test it with curl (replace TOKEN with your actual ical_token from the profiles table):

```bash
curl "https://wnlujkxyknbwergmetab.supabase.co/functions/v1/leave-ics?token=YOUR_TOKEN_HERE"
```

You should get back an ICS file starting with `BEGIN:VCALENDAR`.

## Troubleshooting

### Function returns 401 "Invalid token"
- The token in the URL doesn't match any `ical_token` in the `profiles` table
- Check your profile in the database to get the correct token

### Function returns 500
- Check Supabase function logs: `supabase functions logs leave-ics`
- Environment variables might not be set correctly
- Database permissions might be blocking the query

### Function not found (404)
- The function wasn't deployed successfully
- Re-run the deploy command
- Check deployment status: `supabase functions list`
