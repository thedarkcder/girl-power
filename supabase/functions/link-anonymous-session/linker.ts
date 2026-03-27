export type LinkAnonymousSessionStatus = 'linked' | 'already_linked' | 'relink_rejected';

export function responseForLinkStatus(
  status: string,
): { httpStatus: number; status: LinkAnonymousSessionStatus } {
  switch (status) {
    case 'linked':
    case 'already_linked':
      return { httpStatus: 200, status };
    case 'relink_rejected':
      return { httpStatus: 409, status };
    default:
      throw new Error(`Unexpected link status: ${status}`);
  }
}
