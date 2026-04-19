#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>

@class UISearchBar;

typedef NS_ENUM(NSUInteger, DumperAppType) {
    DumperAppTypeMain,
    DumperAppTypeAll,
    DumperAppTypeUser,
    DumperAppTypeUnity,
};

@interface DumperRootListController : PSListController <UISearchBarDelegate>
@property (nonatomic, assign) DumperAppType appType;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSArray *filteredApps;
@property (nonatomic, strong) NSArray *allApps;
@end
