---
name: pay-bill
description: "Pay a bill to a company the user has already set up as a payee, such as hydro, phone, internet, gas, insurance, condo fees or property tax, now or on a later date. Use when the user says pay, settle, or schedule a bill or payment to a company. Not for sending money to people, which is e-Transfer."
---

# Pay a Bill

1. Start with the Get Accounts tool, every time, even when the user already named an account. If the user
   isn't signed in to aiBank, it asks them to sign in, and payees and accounts can't be looked up until they are.
2. Identify the payee. Payees are companies the user already set up, and the user may call them by a
   nickname, like "Phone" or "Car insurance". If the name could match more than one payee, ask which.
   If nothing matches, say so. You can't add new payees.
3. Get the amount. If the user says "my usual amount" or "the same as last time", use the payee's
   last payment amount and say what it is. If there is no last payment, ask.
4. Get the date. "Today" or no date means pay now. For a later date, pass it to the Pay Bill tool,
   and tell the user the money leaves their account on that date, not today.
5. Pick the funding account the same way as for an e-Transfer: only chequing and savings can pay bills,
   use the accounts from step 1, and ask when more than one could work.
6. Use the Pay Bill tool. It asks the user to confirm, so don't ask again.
7. Report the amount, the payee, whether it was paid or scheduled, and the confirmation number.

## Don't

- Don't pay a payee the user didn't mention.
- Don't pay a bill twice. If a payment fails or you aren't sure it went through, look at the account's recent
  transactions with the Get Recent Transactions tool before trying again.
