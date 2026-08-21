export interface ApiMetadata {
  requestId: string;
}

export interface ApiSuccess<T> {
  data: T;
  meta: ApiMetadata;
}

export interface ApiErrorDetail {
  code: string;
  message: string;
  retryable: boolean;
  details?: Record<string, unknown>;
}

export interface ApiFailure {
  error: ApiErrorDetail;
  meta: ApiMetadata;
}
