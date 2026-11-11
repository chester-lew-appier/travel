# Trip Expense Ledger

A single-page app for logging travel expenses (Meal, Taxi, Others).

- Add expenses by hand: date, type, merchant, optional items, total, currency, who paid, receipt yes/no, notes.
- Amounts stay in the currency on the receipt; totals are shown per currency.
- Take a receipt photo with the phone camera or choose one from the gallery; a small copy is kept with the expense.
- Filter by month, type, "To claim" and "No receipt"; copy the list as CSV for a claim.

## Data

Everything is stored in the browser's `localStorage` on the device that entered it. Nothing is sent to a server.

## Receipt scanning

Automatic reading of receipts (merchant, items, total) uses the Claude artifact runtime (`claude.use("sample")`)
and only works when the page is opened as a Claude artifact. Opened anywhere else, the page still works:
the photo is attached and the details are typed in by hand.

## Run locally

Open `index.html` in a browser. No build step.
