import type { createDataSource } from '@app/data';
import type { Request, Response } from 'express';
import type { ResultType } from './result.js';

/** Route parameters only; not an authorization context or a validation result. */
export type ApiParams = Readonly<Record<string, string | readonly string[] | undefined>>;

/** No session/authentication structure has been agreed or implemented yet. */
export type ApiSession = unknown;

/** Raw HTTP input remains unknown; data is the separately supplied operation payload. */
export type ApiRequest = Request<ApiParams, unknown, unknown>;
export type ApiResponse = Response<unknown>;

/** Existing TypeORM DataSource instance supplied by the caller; never initialized here. */
export type ApiDatabase = ReturnType<typeof createDataSource>;

/** Shared shape for all async ERP prototypes. All seven properties are required. */
export interface ApiFunctionArgs<P = unknown> {
  req: ApiRequest;
  res: ApiResponse;
  session: ApiSession;
  db: ApiDatabase;
  data: P;
  params: ApiParams;
  result: ResultType;
}

/** Generic placeholder signature; concrete payload/output contracts come later. */
export type ApiPrototypeFunction = <P = unknown, T = unknown>(
  arg: ApiFunctionArgs<P>,
) => Promise<T>;
