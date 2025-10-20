import {
  stake,
  unlockRequest,
  getUnlockRequest,
  cancelUnlockRequest,
  claimUnlockRequest,
  getStats,
  getInfo,
  addRewards,
  collectDAOFees,
  collectDeveloperFees,
  pause,
  unpause,
} from './examples';

async function main() {
  await stake();
}

main();
