# Historical one-off files — do not run

These files were moved from `/home/user/` to keep the workspace root clean. They are historical build/conversion helpers and fixture fragments, **not maintained project tooling or runnable test suites**.

## Scripts

`scripts/` contains the earlier scaffold, conversion, SQL-generation, API-prototype and test-relocation scripts. Several describe superseded designs or refer to paths that no longer exist. Running them can overwrite current source, restore obsolete database layouts/locking logic, or undo later changes.

**Do not execute these scripts against the current project.** Keep them only as historical reference. Their contents were preserved during the move; none was executed.

The maintained entity generator remains at `hanouti/data/scripts/generate_entities.py`. The maintained offline SQL validator is at `.test/data/scripts/validate_routines.py`; neither was run for this cleanup.

## Fixture fragments

`fixtures/fixture_setup.txt` and `fixtures/new_lock_fixture_body.sql` are intermediate fragments from an earlier implementation. They are not complete acceptance fixtures and must not be treated as current SQL instructions. Current unexecuted SQL assertions live under `.test/data/sql/`.

## Deliverable

The current downloadable project ZIP is stored separately at `.test/artifacts/hanouti-starter.zip`. The artifacts folder is excluded when packaging the project, so the ZIP never includes itself or older ZIP copies.
