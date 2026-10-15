# Earvin's Brew Cafe & Bakery QR Ordering Website

This repository will contain the Earvin's Brew Cafe & Bakery QR ordering website, built with Next.js, TypeScript, and Tailwind CSS.

## Planned interfaces

- Customer: responsive menu, product options, cart/checkout, and order confirmation.
- Admin: tablet/desktop order queue, order history, product management, and table QR management.

Customers pay for and collect their orders at the counter. Orders use only these statuses: Pending Payment, Preparing, Ready for Pickup, Completed, and Cancelled. Queue numbers will reset daily in Philippine time and display as three digits (for example, `001`).

## Reference materials

The `references/` directory keeps the approved logo, customer and admin design boards, original layout PDF, and source ZIP. The full 80 MiB product-photo source library is retained locally in `references/product-images/` and intentionally excluded from this first commit. Once the final product-image selection is known, add selected assets with Git LFS if they need to be versioned.

## Customer frontend (Phase 1)

Run `npm install`, then `npm run dev` and open http://localhost:3000.
Production: `npm run build` followed by `npm start`.
Checks: `npm run lint`, `npm run typecheck`, and `npm run build`.
Browser checks: `npm run test:e2e` after a build. Tests use locally installed Microsoft Edge at mobile, tablet, and desktop viewport sizes.

Routes: `/menu`, `/product/[id]`, `/cart`, `/order/[id]`, and `/order/[id]/status`.
The demo defaults to Table 5. A table QR opens `/menu?table=N` and keeps that table through customization, checkout, reloads, and confirmation. Prices and availability are examples. Queue numbers increment only within this browser's saved demo orders; they do not reset daily or coordinate across devices. Orders start Pending Payment. Demo staff actions in the admin interface can update their status. No customer controls change order status.

Eight selected product photos and the exact original logo are copied to `public/images/`. In the customer interface, product photos appear only on Menu; admin product management also uses thumbnails and an image preview. Pasta, Meals, and Add-ons initially show empty categories until products are added. Fonts are bundled locally through Fontsource. The source reference library is unchanged.

## Admin frontend (Phase 2)

Open `/admin` (redirects to `/admin/orders`). The admin uses the original header and approved cream tabs, light-gray cards, and green actions.

- `/admin/orders`: active queue with Confirm Payment, Mark Ready, Complete Order, and cancellation. Use **Load demo orders** once to populate examples without replacing existing orders. Completed and Cancelled orders move to history.
- `/admin/history`: terminal orders with item details, totals, dates/times, and a Philippine-time date filter. Older saved demo orders without a timestamp display “Date unavailable”.
- `/admin/products`: search, add, edit, archive/restore, and Available/Sold Out. Product editing includes descriptions, category, prices, sizes, sweetness, existing café images, and PNG/JPG/WebP uploads up to 1 MB. Uploaded images are held in browser storage; storage failures are reported. Archived items disappear from the customer menu. Sold-out items cannot be added, and unavailable cart items block checkout until removed.
- `/admin/tables`: add unique table numbers, real scannable QR previews, PNG downloads, single-table print layout, and deactivate/reactivate. QR links use the current local origin and the table number. Localhost codes work on the host computer only. Inactive tables cannot place new demo orders.

Catalog and order changes persist in localStorage and update other tabs on the same origin. Table selection uses sessionStorage. This is a frontend demonstration, not a synchronized production database: simultaneous writes are not transactional, data is confined to this browser/profile, and clearing browser storage removes demo changes. Image storage is limited by the browser quota. Admin access is an unprotected demo route; authentication, permissions, real queue generation/daily resets, production QR hosting, payment processing, Supabase, and backend APIs are pending. Printed output was verified through browser print media; physical printing depends on the user's printer.

Run `npm run lint`, `npm run typecheck`, `npm run build`, and `npm run test:e2e`. The Edge browser suite exercises the customer and admin workflows at 375, 390, 768, and 1440 pixels, and writes screenshots under ignored `test-results/`.

### Phase 2 file inventory

Created:

- `src/app/admin/page.tsx`, `src/app/admin/layout.tsx`, `src/app/admin/admin.css`
- `src/app/admin/orders/page.tsx`, `src/app/admin/history/page.tsx`, `src/app/admin/products/page.tsx`, `src/app/admin/tables/page.tsx`
- `src/components/admin/admin-shell.tsx`, `src/components/admin/order-card.tsx`, `src/components/admin/product-editor.tsx`, `src/components/admin/table-card.tsx`
- `src/components/catalog-provider.tsx`, `src/components/catalog-product.tsx`, `src/lib/use-local-demo.ts`
- `tests/admin.spec.ts`

Modified:

- `src/app/layout.tsx`, `src/app/menu/page.tsx`, `src/app/cart/page.tsx`, `src/app/product/[id]/page.tsx`
- `src/components/order-provider.tsx`, `src/components/product-form.tsx`, `src/lib/menu.ts`
- `package.json`, `package-lock.json`, `README.md`

Dependencies added: `qrcode` and its TypeScript definitions. Reference files and original source assets are preserved. All Git operations are managed by the project owner.
