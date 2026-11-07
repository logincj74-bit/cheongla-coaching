alter table public.cheongla_winter_promotions alter column ends_at drop not null;

alter policy winter_promotion_public_read on public.cheongla_winter_promotions
  using (enabled and deleted_at is null and (first_open or second_open)
    and (ends_at is null or ends_at > now()));
