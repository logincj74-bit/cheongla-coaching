# v1.7.11 — visible exam-save validation

The supplied iPad screenshots showed the default exam category selected with an empty title, exam date and application deadline. Native required-field validation could stop submission without a persistent explanation beside the save button.

- Prefill the standard exam title initially and on form reset. Keep custom titles available.
- Use explicit form validation with persistent field-level feedback and a status beside Save; focus and scroll to the missing/invalid field. Preserve required semantics and accessible descriptions.
- Normalize datetime-local values with or without seconds to one valid Korea-time timestamp. Check deadline order and opening a registration window in the past before the server call.
- Show save progress, success and server failure within the form. Preserve entered content on server rejection and distinguish saved data from a subsequent list-refresh failure.
- Live rolled-back SQL tests verify owner and manager creation/readback/update across all five categories and student creation denial. Frontend tests verify blank-field guidance, date checks, exact RPC arguments and input retention after failure. No real exams were published during testing.
