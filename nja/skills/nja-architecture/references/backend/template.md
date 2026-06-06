---
id: backend-template
title: "Backend: New Entity Template"
applies_to: backend
layer: template
depends_on:
  - backend-01-entity-basics
  - backend-02-dtos
  - backend-03-repositories
  - backend-04-services
  - backend-05-controllers
source_files: []
related_docs: []
enforcement: recommended
last_updated: "2026-03-01"
---

# Backend: New Entity Template (Copy-Paste Ready)

---

## WHEN TO USE
Use this template when creating a new backend entity. Choose the appropriate complexity tier based on your requirements.

---

## COMPLEXITY TIERS

| Tier | Description | When to Use |
|------|-------------|-------------|
| **Simple** | Basic CRUD, no computed properties | Standard entities with fields and relationships |
| **Medium** | Computed properties, edge metadata | Entities needing counts, samples, or relationship metadata |
| **Complex** | Custom queries, custom business logic | Entities with specialized filtering, bulk operations |

---

## DECISION MATRIX

| Requirement | Tier |
|-------------|------|
| Only fields and relationships | **Simple** |
| Need count/sample computed properties | **Medium** |
| Need custom `buildReturnStatement()` | **Medium** |
| Relationships with edge properties | **Medium** |
| Custom query methods in repository | **Complex** |
| Custom business logic in service | **Complex** |
| Custom/filtered endpoints | **Complex** |

---

## Directory Structure

All tiers follow the same structure:

```
src/features/[domain]/[entity]/
├── [entity].module.ts
├── controllers/
│   └── [entity].controller.ts
├── entities/
│   ├── [entity].ts
│   └── [entity].meta.ts
├── services/
│   └── [entity].service.ts
├── repositories/
│   └── [entity].repository.ts
└── dtos/
    ├── [entity].dto.ts
    ├── [entity].post.dto.ts
    └── [entity].put.dto.ts
```

---

# Tier 1: Simple Entity

**Use when**: Standard CRUD with fields and relationships only.

## Step 1: Metadata

```typescript
// src/features/[domain]/[entity]/entities/[entity].meta.ts
import { DataMeta } from "@carlonicora/nestjs-neo4jsonapi";

export const exampleMeta: DataMeta = {
  type: "examples",
  endpoint: "examples",
  nodeName: "example",
  labelName: "Example",
};
```

## Step 2: Entity & Descriptor

```typescript
// src/features/[domain]/[entity]/entities/[entity].ts
import { Company, defineEntity, Entity, ownerMeta, User } from "@carlonicora/nestjs-neo4jsonapi";
import { exampleMeta } from "./example.meta";

export type Example = Entity & {
  name: string;
  description?: string;
  company: Company;
  owner: User;
};

export const ExampleDescriptor = defineEntity<Example>()({
  ...exampleMeta,

  fields: {
    name: { type: "string", required: true },
    description: { type: "string" },
  },

  relationships: {
    owner: {
      model: ownerMeta,
      direction: "in",
      relationship: "CREATED",
      cardinality: "one",
      dtoKey: "owner",
    },
  },
});

export type ExampleDescriptorType = typeof ExampleDescriptor;
```

## Step 3: DTOs

```typescript
// src/features/[domain]/[entity]/dtos/[entity].dto.ts
import { Type } from "class-transformer";
import { Equals, IsNotEmpty, IsUUID, ValidateNested } from "class-validator";
import { exampleMeta } from "../entities/example.meta";

export class ExampleDTO {
  @Equals(exampleMeta.endpoint)
  type: string;

  @IsUUID()
  id: string;
}

export class ExampleDataDTO {
  @ValidateNested()
  @IsNotEmpty()
  @Type(() => ExampleDTO)
  data: ExampleDTO;
}
```

```typescript
// src/features/[domain]/[entity]/dtos/[entity].post.dto.ts
import { UserDataDTO } from "@carlonicora/nestjs-neo4jsonapi";
import { Type } from "class-transformer";
import { Equals, IsDefined, IsNotEmpty, IsOptional, IsString, IsUUID, ValidateNested } from "class-validator";
import { exampleMeta } from "../entities/example.meta";

export class ExamplePostAttributesDTO {
  @IsDefined()
  @IsNotEmpty()
  @IsString()
  name: string;

  @IsOptional()
  @IsString()
  description?: string;
}

export class ExamplePostRelationshipsDTO {
  @ValidateNested()
  @IsDefined()
  @Type(() => UserDataDTO)
  owner: UserDataDTO;
}

export class ExamplePostDataDTO {
  @Equals(exampleMeta.endpoint)
  type: string;

  @IsUUID()
  id: string;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => ExamplePostAttributesDTO)
  attributes: ExamplePostAttributesDTO;

  @ValidateNested()
  @IsNotEmpty()
  @Type(() => ExamplePostRelationshipsDTO)
  relationships: ExamplePostRelationshipsDTO;
}

export class ExamplePostDTO {
  @ValidateNested()
  @IsNotEmpty()
  @Type(() => ExamplePostDataDTO)
  data: ExamplePostDataDTO;
}
```

## Step 4: Repository (Simple)

```typescript
// src/features/[domain]/[entity]/repositories/[entity].repository.ts
import { AbstractRepository, Neo4jService, SecurityService } from "@carlonicora/nestjs-neo4jsonapi";
import { Injectable } from "@nestjs/common";
import { ClsService } from "nestjs-cls";
import { Example, ExampleDescriptor } from "../entities/example";

@Injectable()
export class ExampleRepository extends AbstractRepository<Example, typeof ExampleDescriptor.relationships> {
  protected readonly descriptor = ExampleDescriptor;

  constructor(
    neo4j: Neo4jService,
    securityService: SecurityService,
    clsService: ClsService,
  ) {
    super(neo4j, securityService, clsService);
  }
  // No overrides needed for simple tier
}
```

## Step 5: Service (Simple)

```typescript
// src/features/[domain]/[entity]/services/[entity].service.ts
import { AbstractService, JsonApiService } from "@carlonicora/nestjs-neo4jsonapi";
import { Injectable } from "@nestjs/common";
import { ClsService } from "nestjs-cls";
import { Example, ExampleDescriptor } from "../entities/example";
import { ExampleRepository } from "../repositories/example.repository";

@Injectable()
export class ExampleService extends AbstractService<Example, typeof ExampleDescriptor.relationships> {
  protected readonly descriptor = ExampleDescriptor;

  constructor(
    jsonApiService: JsonApiService,
    private readonly exampleRepository: ExampleRepository,
    clsService: ClsService,
  ) {
    super(jsonApiService, exampleRepository, clsService, ExampleDescriptor.model);
  }
  // Inherited methods: find, findById, createFromDTO, putFromDTO, delete
}
```

## Step 6: Controller (Simple)

```typescript
// src/features/[domain]/[entity]/controllers/[entity].controller.ts
import {
  Audit,
  AuditService,
  CacheInvalidate,
  CacheService,
  createCrudHandlers,
  createRelationshipHandlers,
  JwtAuthGuard,
  ValidateId,
} from "@carlonicora/nestjs-neo4jsonapi";
import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Post, Put, Query, Res, UseGuards } from "@nestjs/common";
import { FastifyReply } from "fastify";
import { exampleMeta } from "../entities/example.meta";
import { ExamplePostDTO } from "../dtos/example.post.dto";
import { ExamplePutDTO } from "../dtos/example.put.dto";
import { ExampleService } from "../services/example.service";

@UseGuards(JwtAuthGuard)
@Controller()
export class ExampleController {
  private readonly crud = createCrudHandlers(() => this.exampleService);
  private readonly relationships = createRelationshipHandlers(() => this.exampleService);

  constructor(
    private readonly exampleService: ExampleService,
    private readonly cacheService: CacheService,
    private readonly auditService: AuditService,
  ) {}

  @Get(exampleMeta.endpoint)
  async findAll(
    @Res() reply: FastifyReply,
    @Query() query: any,
    @Query("search") search?: string,
    @Query("fetchAll") fetchAll?: boolean,
    @Query("orderBy") orderBy?: string,
  ) {
    return this.crud.findAll(reply, { query, search, fetchAll, orderBy });
  }

  @Get(`${exampleMeta.endpoint}/:exampleId`)
  @Audit(exampleMeta, "exampleId")
  async findById(
    @Res() reply: FastifyReply,
    @Param("exampleId") exampleId: string,
  ) {
    return this.crud.findById(reply, exampleId);
  }

  @Post(exampleMeta.endpoint)
  @CacheInvalidate(exampleMeta)
  async create(
    @Res() reply: FastifyReply,
    @Body() body: ExamplePostDTO,
  ) {
    return this.crud.create(reply, body);
  }

  @Put(`${exampleMeta.endpoint}/:exampleId`)
  @ValidateId("exampleId")
  @CacheInvalidate(exampleMeta, "exampleId")
  async update(
    @Res() reply: FastifyReply,
    @Body() body: ExamplePutDTO,
  ) {
    return this.crud.update(reply, body);
  }

  @Delete(`${exampleMeta.endpoint}/:exampleId`)
  @HttpCode(HttpStatus.NO_CONTENT)
  @CacheInvalidate(exampleMeta, "exampleId")
  async delete(
    @Res() reply: FastifyReply,
    @Param("exampleId") exampleId: string,
  ) {
    return this.crud.delete(reply, exampleId);
  }
}
```

## Step 7: Module

```typescript
// src/features/[domain]/[entity]/[entity].module.ts
import { AuditModule, modelRegistry } from "@carlonicora/nestjs-neo4jsonapi";
import { Module, OnModuleInit } from "@nestjs/common";
import { ExampleController } from "./controllers/example.controller";
import { ExampleDescriptor } from "./entities/example";
import { ExampleRepository } from "./repositories/example.repository";
import { ExampleService } from "./services/example.service";

@Module({
  controllers: [ExampleController],
  providers: [ExampleDescriptor.model.serialiser, ExampleRepository, ExampleService],
  exports: [ExampleRepository],
  imports: [AuditModule],
})
export class ExampleModule implements OnModuleInit {
  onModuleInit() {
    modelRegistry.register(ExampleDescriptor.model);
  }
}
```

---

# Tier 2: Medium Entity

**Adds to Simple**: Computed properties, edge metadata on relationships, custom `buildReturnStatement()`.

## Entity & Descriptor (Medium) - Add computed

```typescript
export type Example = Entity & {
  name: string;
  description?: string;
  photoCount?: number;      // Computed
  samplePhotos?: string[];  // Computed
  company: Company;
  owner: User;
  items?: Item[];           // Relationship with edge properties
};

export const ExampleDescriptor = defineEntity<Example>()({
  ...exampleMeta,

  fields: {
    name: { type: "string", required: true },
    description: { type: "string" },
    photoCount: { type: "number" },
    samplePhotos: { type: "string[]" },
  },

  computed: {
    photoCount: {
      compute: (params) => {
        if (!params.record.has("photoCount")) return params.data?.photoCount;
        const count = params.record.get("photoCount");
        return count?.toNumber ? count.toNumber() : Number(count) || 0;
      },
    },
    samplePhotos: {
      compute: (params) => {
        if (!params.record.has("samplePhotos")) return [];
        const photos = params.record.get("samplePhotos") || [];
        return photos.map((p: any) => p?.properties?.url).filter(Boolean);
      },
    },
  },

  relationships: {
    owner: { /* same as Simple */ },
    items: {
      model: itemMeta,
      direction: "out",
      relationship: "CONTAINS",
      cardinality: "many",
      dtoKey: "items",
      fields: [{ name: "position", type: "number", required: true }],  // Edge property
    },
  },
});
```

## Repository (Medium) - Add buildReturnStatement

```typescript
@Injectable()
export class ExampleRepository extends AbstractRepository<Example, typeof ExampleDescriptor.relationships> {
  protected readonly descriptor = ExampleDescriptor;

  constructor(neo4j: Neo4jService, securityService: SecurityService, clsService: ClsService) {
    super(neo4j, securityService, clsService);
  }

  protected buildReturnStatement(): string {
    return `
      MATCH (${exampleMeta.nodeName}:${exampleMeta.labelName})-[:BELONGS_TO]->(${exampleMeta.nodeName}_${companyMeta.nodeName}:${companyMeta.labelName})
      MATCH (${exampleMeta.nodeName})<-[:CREATED]-(${exampleMeta.nodeName}_${ownerMeta.nodeName}:${ownerMeta.labelName})
      CALL {
        WITH ${exampleMeta.nodeName}
        OPTIONAL MATCH (${exampleMeta.nodeName})-[:CONTAINS]->(item:Item)
        RETURN count(item) as photoCount, collect(item)[0..4] as samplePhotos
      }
      RETURN ${exampleMeta.nodeName}, ${exampleMeta.nodeName}_${companyMeta.nodeName}, ${exampleMeta.nodeName}_${ownerMeta.nodeName}, photoCount, samplePhotos
    `;
  }
}
```

---

# Tier 3: Complex Entity

**Adds to Medium**: Custom repository queries, custom service methods, custom/filtered endpoints.

## Repository (Complex) - Add custom query

```typescript
@Injectable()
export class ExampleRepository extends AbstractRepository<Example, typeof ExampleDescriptor.relationships> {
  // ... Medium tier code ...

  async findPending(params: { cursor: JsonApiCursorInterface }): Promise<Example[]> {
    const query = this.neo4j.initQuery({ serialiser: ExampleDescriptor.model, cursor: params.cursor });
    query.query = `
      ${this.buildDefaultMatch()}
      WHERE ${exampleMeta.nodeName}.status = 'pending'
      ORDER BY ${exampleMeta.nodeName}.createdAt DESC
      {CURSOR}
      ${this.buildReturnStatement()}
    `;
    return this.neo4j.readMany(query);
  }
}
```

## Service (Complex) - Add custom method

```typescript
@Injectable()
export class ExampleService extends AbstractService<Example, typeof ExampleDescriptor.relationships> {
  // ... Medium tier code ...

  async findPending(params: { query: any }): Promise<any> {
    const paginator = new JsonApiPaginator(params.query);
    const data = await this.exampleRepository.findPending({ cursor: paginator.generateCursor() });
    return this.jsonApiService.buildList(ExampleDescriptor.model, data, paginator);
  }
}
```

## Controller (Complex) - Add custom endpoint

Custom endpoints bypass handler factories and call service directly:

```typescript
@UseGuards(JwtAuthGuard)
@Controller()
export class ExampleController {
  private readonly crud = createCrudHandlers(() => this.exampleService);
  private readonly relationships = createRelationshipHandlers(() => this.exampleService);

  constructor(
    private readonly exampleService: ExampleService,
    private readonly cacheService: CacheService,
    private readonly auditService: AuditService,
  ) {}

  // ... Standard CRUD using handlers (same as Simple tier) ...

  // Custom filtered endpoint (bypasses handlers)
  @Get(`${exampleMeta.endpoint}/pending`)
  async findPending(
    @Res() reply: FastifyReply,
    @Query() query: any,
  ) {
    const response = await this.exampleService.findPending({ query });
    reply.send(response);
  }

  // Relationship endpoint with edge properties (bypasses handlers)
  @Post(`${exampleMeta.endpoint}/:exampleId/${itemMeta.endpoint}/:itemId`)
  async addItem(
    @Res() reply: FastifyReply,
    @Param("exampleId") exampleId: string,
    @Param("itemId") itemId: string,
    @Body() body: ExampleItemsAddSingleDTO,
  ) {
    const response = await this.exampleService.addToRelationshipFromDTO({
      id: exampleId,
      relationship: ExampleDescriptor.relationshipKeys.items,
      data: { id: itemId, type: itemMeta.endpoint, meta: body.data?.meta },
    });
    reply.send(response);
  }
}
```

---

## Checklist

Before finishing, verify:
- [ ] Metadata file created with correct type/endpoint/nodeName/labelName
- [ ] Entity type includes all fields and relationships
- [ ] Descriptor has fields, computed (if needed), and relationships
- [ ] DTOs validate all required fields
- [ ] Repository extends AbstractRepository
- [ ] Service extends AbstractService
- [ ] Controller uses handler factories for standard CRUD
- [ ] Controller uses `@ValidateId` on PUT endpoints
- [ ] Controller uses `@CacheInvalidate` on mutation endpoints
- [ ] Controller uses `@Audit` on GET by ID endpoints
- [ ] Module registers model in onModuleInit
- [ ] Module imports AuditModule
