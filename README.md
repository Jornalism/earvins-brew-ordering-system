# Earvin's Brew Cafe & Bakery QR Ordering Website

This repository will contain the Earvin's Brew Cafe & Bakery QR ordering website, built with Next.js, TypeScript, and Tailwind CSS.

## Planned interfaces

- Customer: responsive menu, product options, cart/checkout, and order confirmation.
- Admin: tablet/desktop order queue, order history, product management, and table QR management.

Customers pay for and collect their orders at the counter. Orders use only these statuses: Pending Payment, Preparing, Ready for Pickup, Completed, and Cancelled. Queue numbers will reset daily in Philippine time and display as three digits (for example, `001`).

## Reference materials

The `references/` directory keeps the approved logo, customer and admin design boards, original layout PDF, and source ZIP. The full 80 MiB product-photo source library is retained locally in `references/product-images/` and intentionally excluded from this first commit. Once the final product-image selection is known, add selected assets with Git LFS if they need to be versioned.

No frontend or backend implementation has begun in this commit.
