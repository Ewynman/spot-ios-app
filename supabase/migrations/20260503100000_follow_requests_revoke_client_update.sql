-- Spot never UPDATEs follow_requests (accept/deny/cancel use DELETE + follows insert).
-- Removing UPDATE closes the permissive cross-party update path with zero app change.

drop policy if exists follow_requests_update_parties on public.follow_requests;

revoke update on table public.follow_requests from authenticated;
