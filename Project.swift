import ProjectDescription

let project = Project(
  name: "FideShowcase",
  packages: [
    .package(url: "https://github.com/NSStudent/FideSwiftSDK", from: "0.1.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.13.0"),
  ],
  targets: [
    .target(
      name: "FideShowcase",
      destinations: [.iPhone, .iPad],
      product: .app,
      bundleId: "dev.fideswiftsdk.showcase",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "FIDE Showcase",
        "CFBundleDevelopmentRegion": "es",
        "CFBundleLocalizations": ["es"],
        "UILaunchScreen": [:],
        "UIBackgroundModes": ["fetch"],
        "BGTaskSchedulerPermittedIdentifiers": ["dev.fideswiftsdk.showcase.refresh"],
      ]),
      buildableFolders: [
        "FideShowcase/Sources",
        "FideShowcase/Resources",
      ],
      dependencies: [
        .package(product: "FideSDK"),
        .package(product: "SQLiteData"),
      ],
      settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
      ])
    )
  ]
)
