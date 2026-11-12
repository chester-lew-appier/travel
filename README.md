# Trip Expense Ledger

A shared expense log for a trip with friends. Four people (user1 to user4) each sign in with their own PIN.
Everything anyone enters is visible to all four.

The page has three sections:

1. **Add spending** – type it in, or take/upload a receipt photo and have the receipt name, items and total filled in.
2. **Records** – everyone's records, with today's total and the overall total, filtered by user or all users.
3. **Settle up** – the total is split equally between user1, user2 and user3, and the page works out who pays whom.

Types are Meal, Taxi and Others. Currencies are RMB (the default), MYR and SGD. Amounts stay in the receipt's currency, and each currency is settled separately.

## How the data is stored

Records and receipt photos are saved in a free [Supabase](https://supabase.com) database that you own.
The tables are locked: the page reaches them only through database functions that check the PIN first.
PINs are stored only as bcrypt hashes in the database, not in this repository.
Each person can edit or delete only the records they entered.

## One-time setup (about 10 minutes)

1. **Create the database.** Sign up at supabase.com and create a new project (free plan).
2. **Create the tables and set the PINs.** In the project, open **SQL Editor → New query**.
   Paste the whole of [`supabase/setup.sql`](supabase/setup.sql). At the bottom, replace
   `PIN_FOR_USER1` … `PIN_FOR_USER4` with each person's PIN (all different), then click **Run**.
   It is safe to run again later, for example to change a PIN; existing records are kept.
3. **Connect the page.** In Supabase open **Project Settings → API** (or **Connect**) and copy the
   **Project URL** and the **anon / publishable** key. Do **not** use the `service_role` / secret key.
   On GitHub, open [`config.js`](config.js), click the pencil icon, paste the two values in place of
   `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY`, and click **Commit changes**.
4. **Open the site** at https://chester-lew-appier.github.io/travel/ and sign in with a PIN.

## Good to know

- **Settle up.** Every record counts toward the total, including anything user4 paid. user4 has no share,
  so whatever user4 paid is owed back to them by the others.
- **Receipt scanning** runs in the browser with [Tesseract.js](https://github.com/naptha/tesseract.js) (English, Simplified
  and Traditional Chinese). The first scan downloads the reader. It works best on clear printed receipts and can
  misread, so check the fields before saving.
- **4-digit PINs can be guessed** by someone determined (each wrong try waits 1 second). Don't store anything
  you'd mind leaking.
- **Free Supabase projects pause after about a week with no activity.** If the page can't reach the database,
  open the Supabase dashboard and click **Restore project**.
