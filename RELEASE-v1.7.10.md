# v1.7.10 — student exam applications

- Student application targets now come directly from the verified, approved student's own profile. Student exam/meal applications no longer depend on a parent-child lookup RPC. Parent accounts retain server-verified child lists.
- Show the four standard exam categories in student application screens, with category selection and explicit unpublished-exam messaging. Preserve the existing optional Other category.
- Preserve application-complete/cancel/reapply states and final confirmation. Recheck account identity after confirmation and keep buttons disabled while loading/saving or after a load failure.
- Operational diagnosis: the sole existing exam was soft-deleted; there were no published active exams. It was deliberately left deleted. Actual registration requires staff to publish an exam with a date/deadline.
- Verification: live authenticated synthetic student registers, cancels and re-registers all four categories; duplicate, other-student, deleted and expired safeguards tested in a rolled-back transaction. Frontend flow tests cover the same actions, category visibility and the student/parent applicant paths. No real student registrations created.
