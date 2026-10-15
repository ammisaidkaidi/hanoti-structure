# API common types and helper-porting area

This folder contains API-specific reusable contracts and helpers:

- `types.ts`: the seven-field `ApiFunctionArgs<P>` contract, Express type aliases, the type-only `ApiDatabase` alias, opaque session and prototype signature.
- `result.ts`: **`ResultType = unknown`**, intentionally deferred for discussion.
- `errors.ts`: the explicit internal `ApiNotImplementedError` used by stubs; not an HTTP/result envelope.
- `not-implemented.ts`: a helper that always throws and never creates fake success data.
- `index.ts`: explicit exports.

Port additional API helpers here when their behavior is agreed. Do not copy an authorization/settings algorithm out of SQL or substitute placeholders that return success. There are no authentication, permission, validation, transaction, response-sending or result-building helpers yet.

`packages/common` remains the existing browser/server shared package; these are different responsibilities. Reuse shared utilities through `@app/common` when needed, with an explicit workspace dependency, rather than duplicating them. Keep server-only helpers and trusted session handling out of browser imports. Do not re-export a database client or start connections as an import side effect.

The session and ResultType contracts remain opaque rather than inventing authentication fields or deciding response semantics early. Future porting must retain all established permission, policy, lock, frozen-row and snapshot protections.
