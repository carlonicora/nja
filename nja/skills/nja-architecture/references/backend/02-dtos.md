---
id: backend-02-dtos
title: "Backend: DTOs"
applies_to: backend
layer: dto
depends_on:
  - backend-01-entity-basics
source_files:
  - "apps/api/src/features/*/dtos/*.ts"
related_docs:
  - backend-05-controllers
  - backend-template
enforcement: critical
last_updated: "2026-03-01"
---

# Backend: DTOs (Data Transfer Objects)

---

## WHEN TO USE
Read this file when:
- Creating DTOs for a new entity
- Adding validation to existing DTOs
- Creating relationship DTOs for edge properties

---

## CRITICAL RULES

1. **DTOs match entity definition** - Required in entity = required in POST DTO.
2. **PUT requires all fields** - Full replacement semantics.
3. **PATCH makes all fields optional** - Partial update semantics.
4. **Relationship DTOs for edge properties** - When relationship has `fields`, create dedicated DTOs.
5. **Use `@IsDateString()` for date/datetime attributes** — never `@IsString()`. The descriptor declares the field as `"date"` or `"datetime"`; the DTO is the wire-format guard. See [../date-handling.md](../date-handling.md).

---

## DECISION MATRIX

### Required vs Optional Fields

| DTO Type | Attributes | Relationships |
|----------|------------|---------------|
| **POST** | Required fields = `@IsDefined()`, Optional = `@IsOptional()` | Required relationships = `@IsDefined()` |
| **PUT** | Same as POST (full replacement) | Same as POST |
| **PATCH** | All fields `@IsOptional()` | All relationships `@IsOptional()` |

### When to Create Relationship DTOs

| Question | Answer |
|----------|--------|
| Does relationship have edge properties (fields array)? | **Yes** - Create relationship DTO |
| Is it a simple association without metadata? | **No** - Use standard entity DTO |
| Example: Adding photo with position to gallery | Create `GalleryPhotographsAddSingleDTO` |

---

## COMMON MISTAKES

- Making required fields optional in POST DTO
- Forgetting `@Type(() => ClassName)` decorator for nested validation
- Missing `@ValidateNested()` on nested objects
- Using wrong meta type for relationship DTOs

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [01-entity-basics.md](01-entity-basics.md) | Understand entity field requirements |
| [05-controllers.md](05-controllers.md) | How DTOs are used in controllers |
| [template.md](template.md) | Copy-paste ready DTO code |

---

## JSON:API Request Structure

```json
{
  "data": {
    "type": "galleries",
    "id": "uuid-here",
    "attributes": {
      "name": "My Gallery",
      "description": "A description"
    },
    "relationships": {
      "owner": {
        "data": { "type": "users", "id": "user-uuid" }
      },
      "photographs": {
        "data": [
          { "type": "photographs", "id": "photo-1", "meta": { "position": 1 } }
        ]
      }
    }
  }
}
```

---

## Reference DTO (for relationship references)

```typescript
// gallery.dto.ts
import { Type } from "class-transformer";
import { Equals, IsNotEmpty, IsUUID, ValidateNested } from "class-validator";
import { galleryMeta } from "../entities/gallery.meta";

export class GalleryDTO {
  @Equals(galleryMeta.endpoint)  // Must match type
  type: string;

  @IsUUID()
  id: string;
}

export class GalleryDataDTO {
  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryDTO)
  data: GalleryDTO;
}

export class GalleryDataListDTO {
  @ValidateNested({ each: true })
  @IsNotEmpty()
  @Type(() => GalleryDTO)
  data: GalleryDTO[];
}
```

---

## POST DTO (Create)

```typescript
// gallery.post.dto.ts
import { UserDataDTO } from "@carlonicora/nestjs-neo4jsonapi";
import { Type } from "class-transformer";
import {
  Equals, IsDefined, IsNotEmpty, IsOptional,
  IsString, IsUUID, ValidateNested,
} from "class-validator";
import { galleryMeta } from "../entities/gallery.meta";

// Attributes for creation
export class GalleryPostAttributesDTO {
  @IsDefined()       // Required in entity = @IsDefined()
  @IsNotEmpty()
  @IsString()
  name: string;

  @IsOptional()      // Optional in entity = @IsOptional()
  @IsString()
  description?: string;
}

// Relationships for creation
export class GalleryPostRelationshipsDTO {
  @ValidateNested()
  @IsDefined()       // Required relationship
  @Type(() => UserDataDTO)
  owner: UserDataDTO;
}

// Complete data structure
export class GalleryPostDataDTO {
  @Equals(galleryMeta.endpoint)
  type: string;

  @IsUUID()
  id: string;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPostAttributesDTO)
  attributes: GalleryPostAttributesDTO;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPostRelationshipsDTO)
  relationships: GalleryPostRelationshipsDTO;
}

// Top-level wrapper
export class GalleryPostDTO {
  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPostDataDTO)
  data: GalleryPostDataDTO;
}
```

---

## PUT DTO (Full Update)

```typescript
// gallery.put.dto.ts
import { UserDataDTO } from "@carlonicora/nestjs-neo4jsonapi";
import { Type } from "class-transformer";
import {
  Equals, IsDefined, IsNotEmpty, IsOptional,
  IsString, IsUUID, ValidateNested,
} from "class-validator";
import { galleryMeta } from "../entities/gallery.meta";

export class GalleryPutAttributesDTO {
  @IsDefined()       // Same as POST - full replacement
  @IsNotEmpty()
  @IsString()
  name: string;

  @IsOptional()
  @IsString()
  description?: string;
}

export class GalleryPutRelationshipsDTO {
  @ValidateNested()
  @IsDefined()
  @Type(() => UserDataDTO)
  owner: UserDataDTO;
}

export class GalleryPutDataDTO {
  @Equals(galleryMeta.endpoint)
  type: string;

  @IsUUID()
  id: string;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPutAttributesDTO)
  attributes: GalleryPutAttributesDTO;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPutRelationshipsDTO)
  relationships: GalleryPutRelationshipsDTO;
}

export class GalleryPutDTO {
  @ValidateNested()
  @IsNotEmpty()
  @Type(() => GalleryPutDataDTO)
  data: GalleryPutDataDTO;
}
```

---

## Relationship DTOs (for Edge Properties)

When a relationship has edge properties (defined in entity descriptor's `fields` array), create dedicated DTOs for add/update operations.

### Example: Adding Photo to Gallery with Position

```typescript
// gallery.relationship.dto.ts
import { Type } from "class-transformer";
import { IsDefined, IsNumber, IsOptional, ValidateNested } from "class-validator";

// Meta DTO for edge properties
export class GalleryPhotographsMetaDTO {
  @IsDefined()
  @IsNumber()
  position: number;
}

// Data DTO with optional meta
export class GalleryPhotographsAddSingleDataDTO {
  @ValidateNested()
  @IsOptional()
  @Type(() => GalleryPhotographsMetaDTO)
  meta?: GalleryPhotographsMetaDTO;
}

// Top-level wrapper
export class GalleryPhotographsAddSingleDTO {
  @ValidateNested()
  @IsOptional()
  @Type(() => GalleryPhotographsAddSingleDataDTO)
  data?: GalleryPhotographsAddSingleDataDTO;
}
```

### Example: Adding Person with Access Code

```typescript
// gallery.person.relationship.dto.ts
import { Type } from "class-transformer";
import { IsDefined, IsOptional, IsString, ValidateNested } from "class-validator";

export class GalleryPersonMetaDTO {
  @IsDefined()
  @IsString()
  code: string;

  @IsOptional()
  @IsString()
  expiresAt?: string;
}

export class GalleryPersonAddSingleDataDTO {
  @ValidateNested()
  @IsOptional()
  @Type(() => GalleryPersonMetaDTO)
  meta?: GalleryPersonMetaDTO;
}

export class GalleryPersonAddSingleDTO {
  @ValidateNested()
  @IsOptional()
  @Type(() => GalleryPersonAddSingleDataDTO)
  data?: GalleryPersonAddSingleDataDTO;
}
```

### Using Relationship DTOs in Controller

```typescript
// In gallery.controller.ts
@Post(`${galleryMeta.endpoint}/:galleryId/${photographMeta.endpoint}/:photographId`)
async addPhotograph(
  @Param("galleryId") galleryId: string,
  @Param("photographId") photographId: string,
  @Body() body: GalleryPhotographsAddSingleDTO,
) {
  // body.data.meta contains the edge properties
  const position = body.data?.meta?.position ?? 0;
  // ... add relationship with edge properties
}
```

---

## Error Handling

DTOs automatically throw validation errors when:
- Required fields are missing (`@IsDefined()`)
- Type validation fails (`@IsString()`, `@IsNumber()`, etc.)
- Nested validation fails (`@ValidateNested()`)
- Type mismatch (`@Equals(meta.endpoint)`)

The framework returns 400 Bad Request with validation error details.

---

**Next**: See [03-repositories.md](./03-repositories.md) for data access patterns
