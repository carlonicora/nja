---
id: feature-template
title: "Feature Handbook Template"
applies_to: both
layer: meta
depends_on:
  - core-principles
source_files: []
related_docs: []
enforcement: recommended
last_updated: "2026-03-01"
---

# Feature Handbook Template

> Copy this template to `docs/features/<module-name>.md` when documenting a feature or module.
> Update the frontmatter `id` and `title` fields for each new handbook.
> The quality bar: a fresh Claude instance reads ONLY the handbook and implements correctly without touching source code.

---

## How to Use This Template

1. Copy this file to `docs/features/<module-name>.md`
2. Update the YAML frontmatter (`id`, `title`, `source_files`)
3. Fill in each section based on the actual implementation
4. Ship docs and code on the same branch

---

## Template Starts Here

```markdown
---
id: feature-<module-name>
title: "<Module Name>"
applies_to: both
layer: meta
depends_on:
  - core-principles
source_files:
  - "apps/api/src/features/<domain>/<entity>/"
  - "apps/web/src/features/<domain>/"
related_docs: []
enforcement: recommended
last_updated: "YYYY-MM-DD"
---

# <Module Name>

## Data Model

### Entities

| Entity | Neo4j Label | JSON:API Type | Key Fields |
|--------|-------------|---------------|------------|
| Example | Example | examples | name, description, status |

### Relationships

| From | To | Relationship Type | Direction | Edge Properties |
|------|-----|-------------------|-----------|-----------------|
| Example | Account | BELONGS_TO | out | — |
| Example | User | CREATED | in | — |

## API Endpoints

| Method | Path | Description | Auth | DTO |
|--------|------|-------------|------|-----|
| GET | /examples | List all | JWT | — |
| GET | /examples/:id | Get one | JWT | — |
| POST | /examples | Create | JWT | ExamplePostDTO |
| PUT | /examples/:id | Update | JWT | ExamplePutDTO |
| DELETE | /examples/:id | Delete | JWT | — |

## Business Rules

1. **Rule Name**: Description of the rule, when it applies, and what happens if violated.
2. **Scoping**: All examples are scoped to the authenticated user's company via `buildDefaultMatch()`.
3. **Cascading Deletes**: Describe what happens when this entity is deleted (orphaned relationships, cascade rules).
4. **State Transitions**: If the entity has status values, document valid transitions.
5. **Resource Limits**: Any tier-based or plan-based limits on this entity.

## Edge Cases

- What happens when the entity has no related records?
- What if a required relationship target is deleted?
- Concurrent update behavior
- Empty/null field handling

## Source Files

### Backend
- `apps/api/src/features/<domain>/<entity>/entities/<entity>.ts`
- `apps/api/src/features/<domain>/<entity>/entities/<entity>.meta.ts`
- `apps/api/src/features/<domain>/<entity>/dtos/`
- `apps/api/src/features/<domain>/<entity>/repositories/`
- `apps/api/src/features/<domain>/<entity>/services/`
- `apps/api/src/features/<domain>/<entity>/controllers/`

### Frontend
- `apps/web/src/features/<domain>/data/<Entity>.ts`
- `apps/web/src/features/<domain>/data/<Entity>Interface.ts`
- `apps/web/src/features/<domain>/data/<Entity>Service.ts`
- `apps/web/src/features/<domain>/components/`

## Dashboard / UI Elements

| Page | Element | Action | API Call |
|------|---------|--------|----------|
| List | Data table | Displays all records | GET /examples |
| List | Create button | Opens create form | — |
| Detail | Edit form | Updates record | PUT /examples/:id |
| Detail | Delete button | Confirms and deletes | DELETE /examples/:id |

## Status Values (if applicable)

| Status | Description | Transitions To |
|--------|-------------|----------------|
| draft | Initial state | active, archived |
| active | In use | archived |
| archived | Soft deleted | active |
```
