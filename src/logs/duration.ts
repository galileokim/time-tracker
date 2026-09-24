export function durationSeconds(startedAt: string | Date, endedAt: string | Date): number {
  return Math.floor((new Date(endedAt).getTime() - new Date(startedAt).getTime()) / 1000);
}
