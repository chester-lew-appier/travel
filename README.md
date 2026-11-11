# Trip Expense Ledger

A shared expense log for a trip with friends. Everyone opens the same link, types the passcode,
and adds meals, taxis and other expenses, with a photo of the receipt. Everyone with the passcode
sees and can edit every expense.

- Types: Meal, Taxi, Others.
- Amounts stay in the receipt's currency; totals are shown per currency.
- Take a receipt photo with the phone camera, or choose one from the gallery.
- Filter by month, person, type, "Own money" and "No receipt"; copy the list as CSV.

## How the data is stored

Expenses and receipt photos are saved in a free [Supabase](https://supabase.com) database that you own.
The tables are locked: the page can only reach them through database functions that check the
passcode first, and the passcode is stored only as a bcrypt hash in the database (not in this repository).

## One-time setup (about 10 minutes)

1. **Create the database.** Sign up at supabase.com and create a new project (free plan). Wait until it says it's ready.
2. **Create the tables and set the passcode.** In the project, open **SQL Editor → New query**.
   Paste the whole of [`supabase/setup.sql`](supabase/setup.sql), replace `CHANGE_ME` near the bottom
   with your passcode, and click **Run**. It should say "Success. No rows returned".
3. **Connect the page.** In Supabase open **Project Settings → API** (or the **Connect** button) and copy
   the **Project URL** and the **anon / publishable** key. Do **not** use the `service_role` / secret key.
   On GitHub, open [`config.js`](config.js), click the pencil icon, paste the two values in place of
   `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`, and click **Commit changes**.
4. **Open the site.** After GitHub Pages rebuilds (a minute or two), open
   https://chester-lew-appier.github.io/travel/, enter the passcode and your name.

To change the passcode later, run only the last `insert ... on conflict` statement from `setup.sql`
in the SQL Editor with the new value. Everyone then has to type the new one.

## Good to know

- **The passcode is the only lock.** Anyone who knows it can see, edit and delete every expense and photo.
  A 4-digit code can be guessed by someone determined (each wrong try waits 1 second, but tries can run in parallel);
  a longer passcode is much safer. Don't store anything you'd mind leaking.
- **Free Supabase projects pause after about a week with no activity.** If the page says it can't reach the
  database, open the Supabase dashboard and click **Restore project**.
- **Automatic receipt reading** (merchant, items, total) only works when the page runs inside Claude as an artifact.
  On github.io you attach the photo and type the details.
