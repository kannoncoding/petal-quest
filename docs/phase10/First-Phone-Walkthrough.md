# First Phase 10 phone check — School item and Parent notification

Run when convenient using the Samsung and fictional **Test Family 1**. USB is not required; both apps need internet for this check. Both prepared APKs are already installed. This is a pending walkthrough, not a pass record.

## 1. Prepare the Parent app

1. Open **Petal Quest Parent** on the phone.
2. Tap **Refresh family access**.
3. Confirm it says **Signed in** and **Test Family 1 · parent** (capitalization may differ). Select that family if needed. If you see a different family or need a password you do not know, stop and report that screen's non-sensitive wording.
4. Near the top, find the **Parent notifications** card.
5. Tap **Enable / retry notifications**. If Android asks to allow notifications, tap **Allow**.
6. Wait for **Parent notifications enabled on this device.** If the app instead asks you to sign in and retry, refresh family access and retry once; report a continuing error.
7. Leave Parent open online for about20 seconds to allow registration to finish. The success message alone is not a server registration acceptance result.
8. Optionally note the current earned XP/coin balance; this unscored school item should not change it.

## 2. Prepare the Teen app

1. Open **Petal Quest** (the Teen app). Use this app rather than Live QA.
2. Wait for the launch branding to finish.
3. If you see development previews, tap **Family service access**. If you already see family access/Quests, continue there.
4. Tap **Refresh family access**. Confirm **Signed in**, **Test Family 1 · teen**.
5. Find **Family updates · Enable / retry**, or **Family notifications enabled. · Enable / retry** if it was already enabled. Tap it and allow Android notifications if prompted.
6. Wait for **Family notifications enabled.** and leave the app online for about20 seconds.
7. In the row **Quests | School | Rewards | History**, tap **School**. You should see **At school**.
8. Tap **Refresh school items**. Wait for the progress bar to finish. If the screen remains stale, an error appears, or **Add school item** is disabled, report that wording before creating anything.

## 3. Put Parent in the background

1. Switch back to **Petal Quest Parent** using Android's recent-apps screen.
2. Press the phone's **Home** button or gesture. This leaves Parent in the background.
3. Return to **Petal Quest → Family service access → School**.

## 4. Create one fictional school item

1. Tap **Add school item**.
2. In **What needs to be done?**, enter exactly **Phase 10 fictional permission slip**.
3. Tap **Save** once.
4. Wait for the item to appear in the School list with **Pending · reminders continue at the next school break** and a **Mark completed** button.
5. If the app shows **A saved school request needs confirmation**, it has not yet confirmed the save. Record the message and wait/retry that saved request; do not create another copy.
6. Leave the item pending for this check. The scheduled school-break reminder is separate from the immediate Parent push being checked here.

## 5. Look for the Parent push

1. Allow up to five minutes while the phone remains online. The webhook normally calls promptly; the retry job runs every five minutes.
2. Pull down the notification shade, even if no sound/banner appeared.
3. Look for a notification belonging to **Petal Quest Parent** with text **Open Petal Quest to see a family update.** Its title may simply be **Petal Quest**.
4. Existing older notices may also arrive when a device first registers. Record whether a generic Parent notice arrived after this action; precise event-to-device attribution is a later check.
5. A silent shade entry still counts as displayed. The sound/banner behavior can be checked separately.

## 6. Verify the same item in Parent

1. Open **Petal Quest Parent**.
2. In **Family dashboard**, tap **Refresh dashboard**.
3. If needed select **Teen 1** for the fictional Test Family 1 Teen. There should be a selected Teen before opening the checklist.
4. In the section row **Review | School | Vacation | Adjust | History | Edit | Access**, tap **School**. The row scrolls horizontally if needed.
5. Tap **Refresh school items**.
6. Confirm **Phase 10 fictional permission slip** appears and is still pending.
7. Check that merely creating this item did not award XP/coins. Leave it pending for the next edit-approval check.

## Send back these results

```text
Parent notification setup: enabled / exact error
Teen notification setup: enabled / exact error
Item visible in Teen: yes/no
Item visible in Parent after refresh: yes/no
Generic Parent notification after creation: yes/no
XP/coins unchanged by school-item creation: yes/no
Any error: exact non-sensitive wording
```

If a notification is missing, still complete the Parent refresh check: it distinguishes saved/synchronized data from notification delivery. Avoid uninstalling, clearing data, signing out or repeating database upgrades as troubleshooting steps. No passwords, secret values, health entries or device tokens are needed in the report.

## Following checks, after this result

Teen requests an edit; the original stays visible until a Parent approves. Then Teen marks the item completed; both apps agree and later school reminders stop. Subsequent separate checks cover a local personal reminder, snooze/dismiss/offline restart, Vacation previews and independent family phones.
