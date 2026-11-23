---
name: send-etransfer
description: "Send money to a person by Interac e-Transfer from a chequing or savings account. Use when the user asks to send, e-transfer, etransfer, e-Transfer, or pay a friend or family member money, or to give someone some cash digitally. Not for paying companies or bills, and not for moving money between the user's own accounts."
---

# Send an Interac e-Transfer

1. Start with the Get Accounts tool, every time, even when the user already named an account. If the user
   isn't signed in to aiBank, it asks them to sign in, and contacts and accounts can't be looked up until they are.
2. Make sure the user named one saved contact. If more than one contact could match
   what they said, list the matches and let the user pick. Never guess a contact.
3. Make sure the user gave an amount. If they didn't, ask for it. Never assume one.
4. Work out which account to send from.
   - Use the accounts from step 1. Only chequing and savings accounts can send money.
   - If exactly one of those accounts could cover the amount and the user didn't name an account,
     say which one you will use. If several could, ask the user which to use.
   - If the amount is more than any account can cover, tell the user and stop.
5. If the contact does not have Autodeposit, the user must supply a security question and an answer.
   Ask for them. Remind the user to share the answer with the recipient some other way, not in the message.
6. Use the Send Money by Interac e-Transfer tool. It asks the user to confirm before any money moves,
   so don't ask for a second confirmation yourself.
7. Afterwards, tell the user the amount, the recipient and the confirmation number.

## Don't

- Don't send to a contact the user didn't ask for, and don't split one request into several transfers.
- Don't retry a transfer that failed unless the user asks. A second attempt could send the money twice
  if the first one actually went through. Check the account's recent transactions with the Get Recent Transactions tool first.
