export type LinkAnonymousSessionStatus = 'linked' | 'already_linked';

export function responseForLinkStatus(
  status: string,
): { httpStatus: number; status: LinkAnonymousSessionStatus } {
  switch (status) {
    case 'linked':
    case 'already_linked':
      return { httpStatus: 200, status };
    default:
      throw new Error(`Unexpected link status: ${status}`);
  }
}
