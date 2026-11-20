/// Plain-language help for every problem the server can detect while connecting
/// Facebook, Instagram and Google (see functions/src/lib/oauth/types.ts → IssueCode).
library;

enum GuidanceAction {
  /// Open the platform's sign-in again.
  signInAgain,

  /// Facebook: reopen the permissions screen, including ones the user turned off.
  reviewPermissions,

  /// Re-read profiles with the existing sign-in, after the user fixed something.
  checkAgain,

  /// Connect Instagram directly instead of through a Facebook Page.
  instagramSignIn,
}

class Guidance {
  final String title;
  final String why;
  final List<String> steps;
  final String? helpUrl;
  final String? helpLabel;
  final GuidanceAction action;
  final String actionLabel;
  final GuidanceAction? secondaryAction;
  final String? secondaryLabel;

  /// Warnings still let the user continue (e.g. an unverified Google profile).
  final bool isWarning;

  const Guidance({
    required this.title,
    required this.why,
    required this.steps,
    required this.action,
    required this.actionLabel,
    this.helpUrl,
    this.helpLabel,
    this.secondaryAction,
    this.secondaryLabel,
    this.isWarning = false,
  });
}

const _signInSteps = [
  'Tap the button below. The sign-in page opens in your browser.',
  'Sign in and tap Continue or Allow on every screen.',
  'Come back to Neev Udaan when the page says you are connected.',
];

const Map<String, Guidance> guidance = {
  'LOGIN_CANCELLED': Guidance(
    title: "Sign-in wasn't finished",
    why: 'The sign-in page was closed or access was not allowed, so nothing was connected.',
    steps: _signInSteps,
    action: GuidanceAction.signInAgain,
    actionLabel: 'Try again',
  ),
  'PERMISSIONS_MISSING': Guidance(
    title: 'Some permissions were turned off',
    why: 'Neev Udaan needs to see your Pages and publish posts for you. Some of these switches were turned off '
        'on the Facebook screen.',
    steps: [
      'Tap "Review permissions".',
      'On the Facebook screen, tap "Edit access" (or "Edit settings") if you see it.',
      'Select your business Page and its Instagram account, and keep every switch turned on.',
      'Tap Save, then Continue.',
    ],
    action: GuidanceAction.reviewPermissions,
    actionLabel: 'Review permissions',
  ),
  'NO_PAGES': Guidance(
    title: "We couldn't find a Facebook Page",
    why: 'Apps can only post to Facebook Pages, not personal profiles. Either you have no Page yet, '
        "you aren't an admin of it, or it wasn't selected on the Facebook screen.",
    steps: [
      'If your business already has a Page that someone else runs, ask them to add you: '
          'Page → Settings → Page setup → Page access → Add new → your name → turn on full control.',
      'No Page yet? Create one in 2 minutes using the link below.',
      'Then tap "Connect again" and select your Page on the "Choose Pages" screen.',
    ],
    helpUrl: 'https://www.facebook.com/pages/create',
    helpLabel: 'Create a Facebook Page',
    action: GuidanceAction.reviewPermissions,
    actionLabel: 'Connect again',
  ),
  'NOT_PAGE_ADMIN': Guidance(
    title: "You can't post on this Page",
    why: 'Your role on this Page lets you view it, but not create posts.',
    steps: [
      'Ask a Page admin to open the Page → Settings → Page setup → Page access.',
      'They should give you Facebook access with full control (or at least "Create content").',
      'Then tap "Check again".',
    ],
    action: GuidanceAction.checkAgain,
    actionLabel: 'Check again',
  ),
  'IG_NOT_LINKED': Guidance(
    title: "Instagram isn't linked to this Page",
    why: 'Your Facebook Page will work. To post on Instagram too, link your Instagram account to this Page, '
        'or sign in to Instagram directly.',
    steps: [
      'Open the Instagram app and go to your profile.',
      'Make sure it is a Professional account (see "Switch to Professional" if not).',
      'Tap Edit profile → Page (under "Public business information") → Connect existing Page → choose this Page.',
      'Come back and tap "Check again".',
    ],
    helpUrl: 'https://www.facebook.com/business/help/connect-instagram-to-page',
    helpLabel: 'Step-by-step help from Meta',
    action: GuidanceAction.checkAgain,
    actionLabel: 'Check again',
    secondaryAction: GuidanceAction.instagramSignIn,
    secondaryLabel: 'Sign in with Instagram instead',
    isWarning: true,
  ),
  'IG_PERMISSION_DECLINED': Guidance(
    title: 'Instagram access was turned off',
    why: 'On the Facebook screen, the Instagram permissions were switched off, so we can only post to Facebook.',
    steps: [
      'Tap "Review permissions".',
      'Select your Instagram account and keep its switches turned on.',
    ],
    action: GuidanceAction.reviewPermissions,
    actionLabel: 'Review permissions',
    isWarning: true,
  ),
  'IG_PERSONAL_ACCOUNT': Guidance(
    title: 'This Instagram account is personal',
    why: 'Instagram only lets apps post to Professional accounts. Switching is free, takes a minute, '
        'and keeps all your followers and photos.',
    steps: [
      'In the Instagram app, go to your profile and tap the menu (☰).',
      'Tap Settings and privacy → Account type and tools → Switch to professional account.',
      'Choose "Business", pick a category, and tap Done.',
      'Come back and tap "Sign in again".',
    ],
    helpUrl: 'https://help.instagram.com/502981923235522',
    helpLabel: 'Instagram help: switch to a professional account',
    action: GuidanceAction.signInAgain,
    actionLabel: 'Sign in again',
  ),
  'NO_LOCATIONS': Guidance(
    title: 'No Google Business Profile found',
    why: "This Google account doesn't manage a Business Profile. You may have signed in with a different "
        'Google account than the one that owns your business listing.',
    steps: [
      'Tap "Sign in again" and choose the Google account that owns or manages your business.',
      'If someone else owns the profile, ask them to add you: business.google.com → ⋮ menu → '
          'Business Profile settings → Managers → Add → your email → Manager.',
      'No profile yet? Create one with the link below (Google will ask you to verify it).',
    ],
    helpUrl: 'https://business.google.com/create',
    helpLabel: 'Create a Business Profile',
    action: GuidanceAction.signInAgain,
    actionLabel: 'Sign in again',
  ),
  'NOT_VERIFIED': Guidance(
    title: 'This Google profile is not verified yet',
    why: 'Google only allows verified businesses to publish updates and reply to reviews. '
        'Facebook and Instagram still work while you wait.',
    steps: [
      'Open business.google.com and sign in.',
      'Tap "Get verified" (or "Verify now") on your profile.',
      'Follow Google\'s steps: phone, email, video or postcard. This can take a few days.',
      'When Google confirms, tap "Check again".',
    ],
    helpUrl: 'https://support.google.com/business/answer/7107242',
    helpLabel: 'Google help: verify your business',
    action: GuidanceAction.checkAgain,
    actionLabel: 'Check again',
    isWarning: true,
  ),
  'API_NOT_APPROVED': Guidance(
    title: 'Google connection is waiting for approval',
    why: "Google is still reviewing Neev Udaan's access to Business Profiles. There's nothing you need to do. "
        "We'll switch it on as soon as Google approves.",
    steps: ['You can keep using Facebook and Instagram in the meantime.'],
    action: GuidanceAction.checkAgain,
    actionLabel: 'Check again',
    isWarning: true,
  ),
  'TOKEN_EXPIRED': Guidance(
    title: 'Please sign in again',
    why: 'Your sign-in has expired or was removed, so we can no longer reach this account.',
    steps: _signInSteps,
    action: GuidanceAction.signInAgain,
    actionLabel: 'Sign in again',
  ),
  'UNKNOWN': Guidance(
    title: 'Something went wrong',
    why: "We couldn't finish connecting. This is usually temporary.",
    steps: _signInSteps,
    action: GuidanceAction.signInAgain,
    actionLabel: 'Try again',
  ),
};

Guidance guidanceFor(String code) => guidance[code] ?? guidance['UNKNOWN']!;

/// Issues that stop a profile from being selected at all.
const blockingIssues = {'NOT_PAGE_ADMIN', 'IG_PERSONAL_ACCOUNT'};

/// Short label for an issue badge on a profile tile.
String issueBadge(String code) => switch (code) {
      'NOT_PAGE_ADMIN' => "Can't post here",
      'IG_NOT_LINKED' => 'No Instagram linked',
      'IG_PERMISSION_DECLINED' => 'Instagram access off',
      'IG_PERSONAL_ACCOUNT' => 'Personal account',
      'NOT_VERIFIED' => 'Not verified',
      _ => 'Needs attention',
    };
