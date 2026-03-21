export type LinkAnonymousSessionStatus = 'linked' | 'duplicate' | 'stale_session';

export function responseForLinkStatus(
  status: string,
): { httpStatus: number; status: LinkAnonymousSessionStatus } {
  switch (status) {
    case 'linked':
      return { httpStatus: 200, status };
    case 'duplicate':
      return { httpStatus: 409, status };
    case 'stale_session':
      return { httpStatus: 412, status };
    default:
      throw new Error(`Unexpected link status: ${status}`);
  }
}
