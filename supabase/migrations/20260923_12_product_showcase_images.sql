-- Wholesalers can attach their own images and choose the four catalogue images.
alter table public.products
  add column if not exists custom_image_urls text[] not null default '{}',
  add column if not exists showcase_image_urls text[] not null default '{}';

alter table public.products
  drop constraint if exists products_showcase_image_urls_limit;
alter table public.products
  add constraint products_showcase_image_urls_limit
  check (cardinality(showcase_image_urls) <= 4);
