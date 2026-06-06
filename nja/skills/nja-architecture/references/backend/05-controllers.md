---
id: backend-05-controllers
title: "Backend: Controllers"
applies_to: backend
layer: controller
depends_on:
  - backend-04-services
  - backend-02-dtos
source_files:
  - "apps/api/src/features/*/controllers/*.ts"
related_docs:
  - backend-template
enforcement: critical
last_updated: "2026-03-01"
---

# Backend: Controllers

---

## WHEN TO USE
Read this file when:
- Creating a new controller
- Adding custom endpoints
- Understanding standard CRUD patterns
- Adding relationship endpoints

---

## CRITICAL RULES

1. **Use handler factories for standard CRUD** - `createCrudHandlers()` and `createRelationshipHandlers()`.
2. **Use meta constants for endpoint paths** - Never hardcode endpoint strings.
3. **Use DTOs for request validation** - `@Body() body: EntityPostDTO`.
4. **Use `@ValidateId` on PUT** - Instead of manual ID validation.
5. **Use `@CacheInvalidate` on mutations** - Instead of manual cache invalidation.
6. **Use `@Audit` on GET by ID** - Instead of manual audit logging.
7. **Call service methods, not repository** - Controllers never access repository directly.

---

## HANDLER FACTORIES

Use handler factories to reduce boilerplate. Import from `@carlonicora/nestjs-neo4jsonapi`:

| Factory | Returns | Purpose |
|---------|---------|---------|
| `createCrudHandlers(getService)` | `{ findAll, findById, create, update, patch, delete }` | Standard CRUD operations |
| `createRelationshipHandlers(getService)` | `{ findByRelated, addToRelationship, removeFromRelationship }` | Relationship operations |

**Usage:**
```typescript
private readonly crud = createCrudHandlers(() => this.exampleService);
private readonly relationships = createRelationshipHandlers(() => this.exampleService);
```

> **Note:** Use lambdas (`() => this.service`) because class properties are initialized before constructor runs.

---

## DECLARATIVE DECORATORS

| Decorator | Usage | Purpose |
|-----------|-------|---------|
| `@Audit(meta, "paramId")` | GET by ID | Logs audit entry after response |
| `@CacheInvalidate(meta)` | POST | Invalidates all cache entries for type |
| `@CacheInvalidate(meta, "paramId")` | PUT, DELETE | Invalidates specific cache entry |
| `@ValidateId("paramId")` | PUT | Validates URL param matches body.data.id |

---

## DECISION MATRIX

### When to Add Custom Endpoints

| Question | Endpoint Type |
|----------|---------------|
| Standard CRUD (list, get, create, update, delete)? | **Use handler factories** |
| Filtered list (e.g., `/pending`, `/active`)? | **Custom GET endpoint** |
| Non-resource operation (e.g., `/archive`, `/publish`)? | **Custom POST endpoint** |
| Relationship with edge properties? | **Custom relationship endpoint** |

### Standard vs Custom Endpoints

| Operation | Standard Route | Custom Route Example |
|-----------|---------------|---------------------|
| List all | `GET /galleries` | `GET /galleries/pending` |
| Get one | `GET /galleries/:id` | - |
| Create | `POST /galleries` | - |
| Update | `PUT /galleries/:id` | - |
| Delete | `DELETE /galleries/:id` | - |
| By relationship | `GET /users/:id/galleries` | - |
| Add related with meta | - | `POST /galleries/:id/photographs/:photoId` |

---

## COMMON MISTAKES

- Not using handler factories for standard CRUD
- Hardcoding endpoint strings instead of using meta constants
- Manual ID validation instead of `@ValidateId`
- Manual cache invalidation instead of `@CacheInvalidate`
- Manual audit logging instead of `@Audit`
- Calling repository directly instead of through service
- Missing `@HttpCode(HttpStatus.NO_CONTENT)` on DELETE

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [04-services.md](04-services.md) | Service methods controllers call |
| [02-dtos.md](02-dtos.md) | DTOs for request validation |
| [template.md](template.md) | Copy-paste ready code |

---

## Controller Pattern

```typescript
// gallery.controller.ts
import {
  Audit,
  AuditService,
  CacheInvalidate,
  CacheService,
  createCrudHandlers,
  createRelationshipHandlers,
  JwtAuthGuard,
  ownerMeta,
  ValidateId,
} from "@carlonicora/nestjs-neo4jsonapi";
import {
  Body, Controller, Delete, Get, HttpCode, HttpStatus,
  Param, Post, Put, Query, Res, UseGuards,
} from "@nestjs/common";
import { FastifyReply } from "fastify";
import { GalleryDescriptor } from "../entities/gallery";
import { galleryMeta } from "../entities/gallery.meta";
import { GalleryPostDTO } from "../dtos/gallery.post.dto";
import { GalleryPutDTO } from "../dtos/gallery.put.dto";
import { GalleryService } from "../services/gallery.service";

@UseGuards(JwtAuthGuard)
@Controller()
export class GalleryController {
  private readonly crud = createCrudHandlers(() => this.galleryService);
  private readonly relationships = createRelationshipHandlers(() => this.galleryService);

  constructor(
    private readonly galleryService: GalleryService,
    private readonly cacheService: CacheService,
    private readonly auditService: AuditService,
  ) {}

  // GET /galleries
  @Get(galleryMeta.endpoint)
  async findAll(
    @Res() reply: FastifyReply,
    @Query() query: any,
    @Query("search") search?: string,
    @Query("fetchAll") fetchAll?: boolean,
    @Query("orderBy") orderBy?: string,
  ) {
    return this.crud.findAll(reply, { query, search, fetchAll, orderBy });
  }

  // GET /galleries/:id
  @Get(`${galleryMeta.endpoint}/:galleryId`)
  @Audit(galleryMeta, "galleryId")
  async findById(
    @Res() reply: FastifyReply,
    @Param("galleryId") galleryId: string,
  ) {
    return this.crud.findById(reply, galleryId);
  }

  // POST /galleries
  @Post(galleryMeta.endpoint)
  @CacheInvalidate(galleryMeta)
  async create(
    @Res() reply: FastifyReply,
    @Body() body: GalleryPostDTO,
  ) {
    return this.crud.create(reply, body);
  }

  // PUT /galleries/:id
  @Put(`${galleryMeta.endpoint}/:galleryId`)
  @ValidateId("galleryId")
  @CacheInvalidate(galleryMeta, "galleryId")
  async update(
    @Res() reply: FastifyReply,
    @Body() body: GalleryPutDTO,
  ) {
    return this.crud.update(reply, body);
  }

  // DELETE /galleries/:id
  @Delete(`${galleryMeta.endpoint}/:galleryId`)
  @HttpCode(HttpStatus.NO_CONTENT)
  @CacheInvalidate(galleryMeta, "galleryId")
  async delete(
    @Res() reply: FastifyReply,
    @Param("galleryId") galleryId: string,
  ) {
    return this.crud.delete(reply, galleryId);
  }

  // GET /users/:userId/galleries (nested endpoint)
  @Get(`${ownerMeta.endpoint}/:userId/${GalleryDescriptor.model.endpoint}`)
  async findByOwner(
    @Res() reply: FastifyReply,
    @Param("userId") userId: string,
    @Query() query: any,
    @Query("search") search?: string,
    @Query("fetchAll") fetchAll?: boolean,
    @Query("orderBy") orderBy?: string,
  ) {
    return this.relationships.findByRelated(reply, {
      relationship: GalleryDescriptor.relationshipKeys.owner,
      id: userId,
      query,
      search,
      fetchAll,
      orderBy,
    });
  }
}
```

---

## Custom Endpoint Patterns

### Filtered List Endpoint

Custom endpoints that don't fit standard CRUD bypass handlers and call service directly:

```typescript
// GET /galleries/pending
@Get(`${galleryMeta.endpoint}/pending`)
async findPending(
  @Res() reply: FastifyReply,
  @Query() query: any,
) {
  const response = await this.galleryService.findPendingReviews({ query });
  reply.send(response);
}
```

### Relationship Endpoint with Edge Properties

```typescript
// POST /galleries/:galleryId/photographs/:photographId
@Post(`${galleryMeta.endpoint}/:galleryId/${photographMeta.endpoint}/:photographId`)
async addPhotograph(
  @Res() reply: FastifyReply,
  @Param("galleryId") galleryId: string,
  @Param("photographId") photographId: string,
  @Body() body: GalleryPhotographsAddSingleDTO,
) {
  const response = await this.galleryService.addToRelationshipFromDTO({
    id: galleryId,
    relationship: GalleryDescriptor.relationshipKeys.photograph,
    data: { id: photographId, type: photographMeta.endpoint, meta: body.data?.meta },
  });
  reply.send(response);
}
```

### Non-Resource Operation

```typescript
// POST /galleries/:galleryId/archive
@Post(`${galleryMeta.endpoint}/:galleryId/archive`)
@HttpCode(HttpStatus.NO_CONTENT)
@CacheInvalidate(galleryMeta, "galleryId")
async archive(
  @Res() reply: FastifyReply,
  @Param("galleryId") galleryId: string,
) {
  await this.galleryService.archive({ id: galleryId });
  reply.send();
}
```

---

## Error Handling

Controllers handle errors automatically via NestJS exception filters:
- **400 Bad Request**: DTO validation failures
- **404 Not Found**: Service throws `NotFoundException`
- **412 Precondition Failed**: `@ValidateId` validation failure
- **500 Internal Server Error**: Unhandled exceptions

```typescript
// These exceptions are thrown and handled automatically
throw new NotFoundException(`Gallery with id ${id} not found`);
throw new BadRequestException("Invalid operation");
```

---

**Next**: See [template.md](./template.md) for copy-paste ready code
