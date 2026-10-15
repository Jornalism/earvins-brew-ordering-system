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
The demo uses Table 5, local mock product data, and browser local storage for the cart and orders. Prices and availability are examples. Queue numbers increment only within this browser's saved demo orders; they do not reset daily or coordinate across devices. Orders stay Pending Payment until a future backend provides status updates. The five allowed statuses are modeled with customer pickup messages. No customer controls change order status.

Eight selected product photos and the exact original logo are copied to `public/images/`. Product photos appear only on the Menu page. Pasta, Meals, and Add-ons show empty categories until confirmed product information is available. Fonts are bundled locally through Fontsource. The source reference library is unchanged.

No admin, backend, Supabase, or payment integration is implemented. All Git operations are managed by the project owner.
