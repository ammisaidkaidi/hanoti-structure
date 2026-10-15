# Algerian customer and supplier declarations

**Status: SQL declarations only; not applied. Sources reviewed on 15 October 2026.**

Both `erp.customers` and `erp.suppliers` in the **hanouti** database now declare the same professional/legal profile fields. This is a source-informed data model, **not a certification of legal compliance**. Confirm current obligations for your activity, customer category, tax regime, and document type with an Algerian accountant or legal adviser before enforcing invoice-issuance rules.

## Added fields

| Group                           | Columns                                                              | Design                                                                                    |
| ------------------------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Party identity                  | `party_type`, `first_name`, `last_name`, `legal_name`, `legal_form`  | Distinguish natural and legal persons without forcing a type on incomplete draft records  |
| Job information                 | `job_title`, `job_info`                                              | Free-text occupation/title and relevant professional details                              |
| Business activity               | `business_activity`, `activity_code`                                 | Activity description and optional externally assigned activity code                       |
| Contact                         | `contact_person_name`, `fax`                                         | Supplement existing email, phone, address, and display name                               |
| Fiscal/statistical              | `nif`, `nis`, `article_imposition`                                   | Separate identifiers, not interchangeable                                                 |
| Commercial registration         | `rc`                                                                 | Registration number as supplied on the authoritative document                             |
| National identification         | `nin`                                                                | Optional identifier of the party itself, not automatically its contact person             |
| Other professional registration | `professional_registration_type`, `professional_registration_number` | Paired type/number for an applicable professional register or authorization               |
| Capital                         | `share_capital`, `share_capital_currency`                            | Optional nonnegative capital amount and its three-letter currency code, supplied together |

All added fields are **nullable**. Supplied text must not be blank. `party_type` is `natural_person` or `legal_person`; this is a software classification, not an assertion that every legal form has identical legal obligations. Job details describe the individual or relevant business role; a legal entity's principal activity belongs in `business_activity`.

The existing `name` remains a required display name. Use `first_name`/`last_name` or `legal_name` when legally required on an issued document; a display label alone is not assumed sufficient. Existing `tax_identifier` is retained for compatibility/foreign references, but **`nif` is the canonical Algerian fiscal identifier**. Do not maintain competing Algerian NIF values in both columns.

## Identifier formats and legal basis

### NIF — Numéro d’identification fiscale

The CNRC's published NIF guidance describes **15 positions normally**, extended to **20 positions** for subdivisions such as secondary establishments, units, and branches. The format is not simply “15 for individuals and 20 for companies.” [1](https://cnrcinfo.cnrc.dz/numero-didentification-fiscale-nif/)

Implementation: `VARCHAR(20)`, accepting exactly 15 or 20 ASCII digits when non-NULL. Leading zeros are preserved. No automatic derivation, checksum validation, or DGI authentication is implemented. The direct CNRC page was under maintenance during review; the cited official page's indexed text supplied the format description.

### NIS — Numéro d’identification statistique

Articles 4 and 5 of Executive Decree **97-396 of 28 October 1997**, published by the ONS, specify a **15-digit** NIS and an additional **3-digit** sequential number for secondary establishments/units. [1](https://www.ons.dz/IMG/pdf/NIS.pdf)

Implementation: `VARCHAR(18)`, accepting a 15-digit principal number or the combined 18-digit establishment number. This is a storage-format check, not ONS verification. It remains distinct from NIF and RC.

### NIN — Numéro d’identification national unique

Executive Decree **23-316 of 6 September 2023**, articles 3 and 6, covers natural persons and legal persons and specifies an **18-digit** NIN. Article 14 repeals the older decree 10-210. Do not impose an outdated “NIN only for natural persons” constraint. See the official Journal, pages 4–5. [4](https://www.joradp.dz/FTP/jo-francais/2023/F2023060.pdf)

Implementation: nullable `VARCHAR(18)` with an 18-digit format check. No control-key calculation or official identity authentication is implemented. A format-valid value does not prove an identity, and this column does not authorize collection or access to a national registry.

### RC and invoice identity

The Ministry of Commerce's invoice guidance, referencing Executive Decree **05-468 of 10 December 2005**, lists identity/name, legal form, nature of activity, address/contact details, RC and NIS for the relevant economic-party invoice details, and capital where applicable for the seller. It separately states that a consumer buyer's invoice identifies the buyer by name, given name(s), and address. [1](https://www.commerce.gov.dz/fr/questions-frequentes/themes/facture)

Implementation: `rc` is a nonblank optional `VARCHAR(64)`. No fixed-width numeric RC regex is asserted here; preserve the official reference's letters and separators. The additional legal-identity/activity/capital fields support those document details but do not by themselves produce a legally valid invoice.

For professions with another applicable register or authorization, the ONS decree's identification provisions refer to commercial, craft, and professional-authorization references. The paired generic registration fields provide room for the applicable document instead of pretending every party must have an RC. [1](https://www.ons.dz/IMG/pdf/NIS.pdf)

`article_imposition` is provided as an optional supporting tax-file reference. **No universal mandatory status or fixed statutory length is asserted** in this draft. Its 32-character storage limit is an application choice; check actual fiscal documentation. Likewise, the activity-code and registration-field lengths are technical choices, not claimed legal format specifications.

## Validation boundaries

- NIF, NIS, NIN, and RC remain strings, not numeric quantities. Normalize source-document whitespace before storing digit-only identifiers, without discarding leading zeros.
- Requiredness must be checked at the relevant business workflow (for example before issuing a professional invoice), not inferred from nullable draft/master-data fields. Neither a missing value nor a format-valid value establishes a legal exemption or compliance.
- Non-unique partial indexes on NIF, NIS, and RC support lookups. Branch/contact records can share principal identifiers; a party may also be both customer and supplier. No global uniqueness or cross-table identity reconciliation is imposed.
- NIN is not automatically copied from a representative/contact into a company's party identity. Validate which subject the document identifies.
- There is no authoritative verification API call, tax registration, invoice renderer, data backfill, or credential collection in this change.
- When implementing issued documents, snapshot only the legally relevant identity details so later master-data edits do not silently rewrite historical documents. Existing order snapshot JSON fields do not enforce this policy automatically.

## Privacy and security before real data collection

The ANPDP identifies personal-data processing duties under Law **18-07 of 10 June 2018**, as amended by Law **25-11 of 24 July 2025**, and publishes guidance on declarations/authorizations and processing obligations. The applicable steps depend on the processing being introduced; review them before collecting production identifiers. [1](https://plaintes.anpdp.dz/notice.php) [2](https://anpdp.dz/fr/quelles-sont-vos-obligations/)

Recommended implementation safeguards (not implemented by this DDL):

- Document a lawful purpose and collect only necessary identity/job information. Do not require NIN for every retail sale merely because a database column exists.
- Restrict and mask identifier access, keep raw identifiers out of normal logs and browser list payloads, and establish retention/deletion procedures.
- Select appropriate encryption and key management before storing real identifiers. These columns are ordinary text at the SQL level; **no application-layer encryption or access controls have been implemented**.
- Do not feed NIN, fiscal identifiers, or unnecessary personal/job details into `customers.embedding` or external embedding services. Embeddings are not a substitute for access controls or a guarantee of anonymization. No embedding generation is currently configured.
- Treat the daily database dumps as private identity-bearing backups. The existing backup job does not encrypt archives or automatically delete expired backups; complete storage protection and retention policies before production use.
