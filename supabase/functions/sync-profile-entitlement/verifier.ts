import { Buffer } from 'node:buffer';
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
} from 'npm:@apple/app-store-server-library@3.0.0';
import { HttpError } from '../demo-quota/http.ts';
import { appleRootCertificates } from './apple_root_certificates.ts';

const defaultBundleId = 'com.route25.GirlPower';
const defaultProductIds = ['com.girlpower.app.pro.monthly'];

export type VerifiedEntitlement = {
  environment: string;
  transactionId: string;
  productId: string;
  originalTransactionId: string | null;
};

type VerificationConfig = {
  allowLocalTesting: boolean;
  appAppleId?: number;
  bundleId: string;
  productIds: Set<string>;
};

export interface EntitlementVerifying {
  verifyActiveEntitlement(transactionJws: string): Promise<VerifiedEntitlement>;
}

export function createEntitlementVerifier(options?: Partial<VerificationConfig>): EntitlementVerifying {
  const config = {
    allowLocalTesting: options && 'allowLocalTesting' in options
      ? options.allowLocalTesting ?? allowLocalTestingByDefault()
      : allowLocalTestingByDefault(),
    appAppleId: options ? options.appAppleId : appAppleIdFromEnv(),
    bundleId: options?.bundleId ?? (options ? defaultBundleId : bundleIdFromEnv()),
    productIds: options?.productIds ?? (options ? new Set(defaultProductIds) : productIdsFromEnv()),
  };

  const verifiers = environmentsFor(config).map((environment) => ({
    environment,
    verifier: new SignedDataVerifier(
      appleRootCertificates.map((certificate) => Buffer.from(certificate)),
      false,
      environment,
      config.bundleId,
      environment === Environment.PRODUCTION ? config.appAppleId : undefined,
    ),
  }));

  return {
    async verifyActiveEntitlement(transactionJws: string): Promise<VerifiedEntitlement> {
      let lastVerificationError: VerificationException | null = null;

      for (const candidate of verifiers) {
        try {
          const payload = await candidate.verifier.verifyAndDecodeTransaction(transactionJws);
          const productId = payload.productId ?? '';
          if (config.productIds.has(productId) === false) {
            throw new HttpError(403, 'Unsupported App Store product');
          }
          if (payload.revocationDate) {
            throw new HttpError(403, 'Revoked App Store entitlement');
          }
          if (payload.expiresDate == null || payload.expiresDate <= Date.now()) {
            throw new HttpError(403, 'Expired App Store entitlement');
          }
          if (!payload.transactionId) {
            throw new HttpError(403, 'Missing App Store transaction identifier');
          }

          return {
            environment: payload.environment ?? candidate.environment,
            transactionId: payload.transactionId,
            productId,
            originalTransactionId: payload.originalTransactionId ?? null,
          };
        } catch (error) {
          if (error instanceof HttpError) {
            throw error;
          }
          if (error instanceof VerificationException) {
            lastVerificationError = error;
            continue;
          }
          throw error;
        }
      }

      throw new HttpError(
        403,
        lastVerificationError?.message ?? 'Verified App Store entitlement required',
      );
    },
  };
}

function environmentsFor(config: VerificationConfig): Environment[] {
  const environments: Environment[] = [];
  if (config.allowLocalTesting) {
    environments.push(Environment.XCODE, Environment.LOCAL_TESTING);
  }
  environments.push(Environment.SANDBOX);
  if (config.appAppleId != null) {
    environments.push(Environment.PRODUCTION);
  }
  return environments;
}

function productIdsFromEnv(): Set<string> {
  const raw = Deno.env.get('APPLE_PRO_PRODUCT_IDS');
  if (!raw) {
    return new Set(defaultProductIds);
  }
  const values = raw
    .split(',')
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  return new Set(values.length > 0 ? values : defaultProductIds);
}

function bundleIdFromEnv(): string {
  return Deno.env.get('APPLE_BUNDLE_ID') ?? defaultBundleId;
}

function appAppleIdFromEnv(): number | undefined {
  const raw = Deno.env.get('APPLE_APPLE_ID');
  if (!raw) return undefined;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function allowLocalTestingByDefault(): boolean {
  const override = Deno.env.get('APPLE_ALLOW_LOCAL_TESTING');
  if (override != null) {
    return override === '1' || override.toLowerCase() === 'true';
  }

  try {
    const url = new URL(Deno.env.get('SUPABASE_URL') ?? '');
    return ['127.0.0.1', 'localhost'].includes(url.hostname);
  } catch {
    return false;
  }
}
