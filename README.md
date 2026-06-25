# AirCopy

AirCopy lets you copy on one Mac and paste on another.

## How to use

1. Install AirCopy on every Mac you want to use it on.
2. Open AirCopy and turn on Sync.
3. Allow Local Network access when macOS asks.
4. Keep AirCopy running on each Mac.
5. Copy on one Mac and paste on another.

AirCopy syncs text, images, and recent clipboard history between nearby Macs you control.

## App Store subscription

AirCopy uses StoreKit auto-renewable subscriptions for App Store distribution. Create a monthly subscription product in App Store Connect with this product ID:

```text
dev.aircopy.app.pro.monthly
```

Set the subscription price to $9.99/month and add a 7-day free trial introductory offer in App Store Connect. The app grants sync access while StoreKit reports an active entitlement for that product.

For team billing in the Mac App Store build, keep StoreKit as the unlock path. A direct-download edition can use Stripe Billing later for seat-based invoices, admin-managed teams, SSO, and cross-platform licensing, but that should be a separate distribution path so the App Store app remains review-friendly.

## License

MIT
