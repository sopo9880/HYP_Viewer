/// Navigation contract shared by the HYP, WEB and SERIES workspaces.
///
/// HYP keeps its original six pages. WEB and SERIES use their own page labels
/// and data content, but reuse the existing dashboard shell and controls.
enum ViewerMode { hyp, web, series }

extension ViewerModeNavigation on ViewerMode {
  String get title => switch (this) {
    ViewerMode.hyp => 'HYP Viewer',
    ViewerMode.web => 'WEB Viewer',
    ViewerMode.series => 'SERIES Viewer',
  };

  String get initialPage => switch (this) {
    ViewerMode.hyp => 'home',
    ViewerMode.web => 'favorites',
    ViewerMode.series => 'home',
  };

  List<String> get pages => switch (this) {
    ViewerMode.hyp => const [
      'home', 'library', 'favorites', 'downloads', 'history', 'settings',
    ],
    ViewerMode.web => const [
      'home', 'favorites', 'library', 'downloads', 'settings',
    ],
    ViewerMode.series => const [
      'home', 'library', 'downloads', 'settings',
    ],
  };

  /// Use the same mobile navigation as v0.5.0 in HYP and WEB.
  List<String> get mobilePages => switch (this) {
    ViewerMode.hyp || ViewerMode.web => const [
      'favorites', 'library', 'home', 'downloads', 'settings',
    ],
    ViewerMode.series => const ['home', 'library', 'downloads', 'settings'],
  };

  bool containsPage(String page) => pages.contains(page);

  String contentSection(String page) => switch (this) {
    ViewerMode.hyp => page,
    ViewerMode.web => switch (page) {
      'favorites' => 'web',
      'library' => 'library',
      'downloads' => 'downloads',
      'settings' => 'settings',
      _ => 'home',
    },
    ViewerMode.series => switch (page) {
      'library' => 'series_library',
      'downloads' => 'series_downloads',
      'settings' => 'series_settings',
      _ => 'series_home',
    },
  };
}
