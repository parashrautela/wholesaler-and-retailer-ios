# App Store Review: response and notes draft

Prepared from the current project and App Store Connect state. Replace every bracketed item and confirm the checklist before pasting this into App Store Connect. Do not submit this draft as-is.

## App Review Information → Notes

Jewel India is a B2B jewellery catalogue and business communication app for jewellery wholesalers, retailers, and their authorized employees in India. Wholesalers publish jewellery designs and product details; retailers browse catalogues, contact wholesalers, and manage enquiries/orders; employees access the retailer account features assigned to them. The app helps jewellery businesses share product information and coordinate wholesale enquiries and orders.

### Sign-in and review steps

Sign-in is available with email and password, Google, and Apple. Phone-number sign-in is not supported. Use the demo credentials entered in App Store Connect’s Sign-In Information fields for each role:

- Wholesaler: use the wholesaler demo credentials in Sign-In Information.
- Retailer: use the retailer demo credentials in Sign-In Information.
- Employee: use the employee demo credentials in Sign-In Information. [Confirm the employee demo account is linked to the intended retailer before submitting.]

After signing in, use the role’s home screen to open its catalogue, product details, enquiries/chat, and order features. [Add exact taps/navigation labels after confirming against the release build.]

Account deletion is available from the profile page. [Add exact navigation labels and confirm the recording demonstrates the complete deletion flow.]

### Video

A screen recording made on a physical iPhone running the latest available iOS is attached. It begins by launching the app and demonstrates the normal role-based experience, including sign-in, key catalogue/enquiry/order flows, and account deletion. [Confirm the recording shows each required flow that is present.]

### User-generated content and safety

The app includes user-provided profile/product information, product images, and business conversations. [Confirm whether the release build provides content/user reporting and blocking controls, and give the exact navigation path here. If no such controls exist, do not claim they do; resolve the gap before resubmission or explain accurately to App Review.]

### External services

- Supabase: authentication, database, file storage, and server-side/Edge Function operations.
- Google Sign-In: Google account authentication.
- Sign in with Apple: Apple account authentication.
- Railway-hosted AI image service: AI-assisted jewellery image processing/generation.
- Apple StoreKit and App Store Server Notifications: [include only if the submitted build exposes working in-app credit purchases; confirm products are approved/available and tested before describing them as working].

[Confirm there is no active Razorpay or other external payment checkout in the submitted iOS build. Do not list dormant code as a service used by this release.]

### Regions and content rights

[State the actual App Store availability. The account currently showed 175 territories; confirm EU distribution is disabled before saying the app is not distributed in the EU.]

The app is a jewellery business catalogue and communication tool. [Confirm that all third-party images, trademarks, and other content shown in the app are either owned/licensed or otherwise authorized, and provide relevant documentation if App Review requests it.]

[Confirm whether any regulated service is offered. Do not make a broad legal claim without the account owner’s confirmation.]

## App Review reply draft

Hello App Review,

Thank you for explaining the additional information needed for review. We have added the requested app purpose, audience, access instructions, demo-account details, external-service information, regional availability, and content-rights context to the App Review Notes.

We have also attached a screen recording captured on a physical device running the latest available iOS. The recording starts by launching the app and demonstrates the normal user flow, including [list only the flows actually visible in the recording: sign-in/registration, wholesaler catalogue, retailer catalogue/enquiry/order, employee access, account deletion, UGC reporting/blocking, and any paid feature].

[Add a concise, accurate response about reporting/blocking controls and whether paid features are available in this build.]

Please let us know if you need any additional information to review Jewel India.

Regards,
Jewel India

## Must verify before using this draft

- [ ] Attach the physical-device screen recording; make sure it starts at app launch and shows the real release build.
- [ ] Confirm employee demo account’s relationship to the intended retailer; ensure all three demo accounts remain active and credentials work.
- [ ] Add exact in-app navigation paths, matching the submitted build.
- [ ] Verify whether report/block controls exist for user content/conversations and include them in the video/notes; otherwise fix or accurately disclose the gap.
- [ ] Resolve App Privacy metadata: App Store Connect currently says “Data Not Collected,” which appears inconsistent with account sign-in, business profiles, catalogues, uploaded images, chat, and order data. Audit collection/sharing against the app and its SDKs and correct the privacy answers before resubmission.
- [ ] Decide the submitted build’s credit purchase state. Current App Store Connect products are drafts/“Prepare for Submission,” pricing and the Paid Apps Agreement are incomplete, and the current app screen has shown “App Store credit packs are not available yet.” Either complete and test the IAP setup and submit the IAP with the app, or remove/disable the purchase UI for this build. Do not describe purchases as available unless they work in the review build.
- [ ] Confirm the actual territory list before stating regional availability; user intent is to exclude the EU, but the current account displayed 175 territories.
- [ ] Audit App Store screenshots to ensure they show the real app in use, not only title art or login/splash screens.
- [ ] Confirm all third-party content rights and whether any regulated services/content apply.
- [ ] Select the intended current build for the new submission; the reviewed version previously had build 24 attached, while build 28 was shown as Ready to Submit in TestFlight.
