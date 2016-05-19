//
//  STPSourceListViewController.m
//  Stripe
//
//  Created by Jack Flintermann on 1/12/16.
//  Copyright © 2016 Stripe, Inc. All rights reserved.
//

#import "STPPaymentMethodsViewController.h"
#import "STPBackendAPIAdapter.h"
#import "STPAPIClient.h"
#import "STPToken.h"
#import "STPCard.h"
#import "NSArray+Stripe_BoundSafe.h"
#import "UINavigationController+Stripe_Completion.h"
#import "UIViewController+Stripe_ParentViewController.h"
#import "STPAddCardViewController.h"
#import "STPCardPaymentMethod.h"
#import "STPApplePayPaymentMethod.h"
#import "STPPaymentContext.h"
#import "STPPaymentMethodTuple.h"
#import "STPPaymentActivityIndicatorView.h"
#import "UIImage+Stripe.h"
#import "NSString+Stripe_CardBrands.h"
#import "UITableViewCell+Stripe_Borders.h"
#import "STPPaymentMethodsViewController+Private.h"
#import "STPPaymentContext+Private.h"
#import "UIBarButtonItem+Stripe.h"

static NSString *const STPPaymentMethodCellReuseIdentifier = @"STPPaymentMethodCellReuseIdentifier";
static NSInteger STPPaymentMethodCardListSection = 0;
static NSInteger STPPaymentMethodAddCardSection = 1;

@interface STPPaymentMethodsViewController()<UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, weak)id<STPBackendAPIAdapter> apiAdapter;
@property(nonatomic, weak)STPAPIClient *apiClient;
@property(nonatomic, weak)STPPromise<STPPaymentMethodTuple *> *loadingPromise;
@property(nonatomic)NSArray<id<STPPaymentMethod>> *paymentMethods;
@property(nonatomic)id<STPPaymentMethod> selectedPaymentMethod;
@property(nonatomic, weak)STPPaymentActivityIndicatorView *activityIndicator;
@property(nonatomic)UIBarButtonItem *backItem;
@property(nonatomic)UIBarButtonItem *cancelItem;
@property(nonatomic, weak)UITableView *tableView;
@property(nonatomic, weak)UIImageView *cardImageView;
@property(nonatomic)BOOL loading;

@end

@implementation STPPaymentMethodsViewController

- (instancetype)initWithPaymentContext:(STPPaymentContext *)paymentContext {
    STPAPIClient *apiClient = [[STPAPIClient alloc] initWithPublishableKey:paymentContext.publishableKey];
    self = [self initWithAPIClient:apiClient APIAdapter:paymentContext.apiAdapter loadingPromise:paymentContext.currentValuePromise];
    self.theme = paymentContext.theme;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    STPPaymentActivityIndicatorView *activityIndicator = [STPPaymentActivityIndicatorView new];
    activityIndicator.animating = YES;
    [self.view addSubview:activityIndicator];
    self.activityIndicator = activityIndicator;
    
    UITableView *tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    tableView.allowsMultipleSelectionDuringEditing = NO;
    tableView.alpha = 0;
    tableView.dataSource = self;
    tableView.delegate = self;
    [tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:STPPaymentMethodCellReuseIdentifier];
    tableView.sectionHeaderHeight = 30;
    tableView.separatorInset = UIEdgeInsetsMake(0, 18, 0, 0);
    self.tableView = tableView;
    [self.view addSubview:tableView];
    
    UIImageView *cardImageView = [[UIImageView alloc] initWithImage:[UIImage stp_largeCardFrontImage]];
    cardImageView.contentMode = UIViewContentModeCenter;
    cardImageView.frame = CGRectMake(0, 0, self.view.bounds.size.width, cardImageView.bounds.size.height + (57 * 2));
    self.cardImageView = cardImageView;
    self.tableView.tableHeaderView = cardImageView;
    
    self.navigationItem.title = NSLocalizedString(@"Choose Payment", nil);
    self.backItem = [UIBarButtonItem stp_backButtonItemWithTitle:NSLocalizedString(@"Back", nil) style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    self.cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    __weak typeof(self) weakself = self;
    [self.loadingPromise onSuccess:^(__unused STPPaymentMethodTuple *value) {
        [UIView animateWithDuration:0.2 animations:^{
            NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 1)];
            [weakself.tableView reloadSections:indexSet withRowAnimation:UITableViewRowAnimationAutomatic];
            weakself.tableView.alpha = 1;
        } completion:^(__unused BOOL finished) {
            weakself.activityIndicator.animating = NO;
        }];
    }];
    self.loading = YES;
    [self updateAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    self.navigationItem.leftBarButtonItem = [self stp_isRootViewControllerOfNavigationController] ? self.cancelItem : self.backItem;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tableView.frame = self.view.bounds;
    self.activityIndicator.center = self.view.center;
    if (self.navigationController.navigationBar.translucent) {
        CGFloat insetTop = CGRectGetMaxY(self.navigationController.navigationBar.frame);
        self.tableView.contentInset = UIEdgeInsetsMake(insetTop, 0, 0, 0);
        self.tableView.scrollIndicatorInsets = self.tableView.contentInset;
    } else {
        self.tableView.contentInset = UIEdgeInsetsZero;
        self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
    }
}

- (void)setTheme:(STPTheme *)theme {
    _theme = theme;
    [self updateAppearance];
}

- (void)updateAppearance {
    [self.backItem stp_setTheme:self.theme];
    [self.cancelItem stp_setTheme:self.theme];
    self.tableView.backgroundColor = self.theme.primaryBackgroundColor;
    self.view.backgroundColor = self.theme.primaryBackgroundColor;
    self.tableView.tintColor = self.theme.accentColor;
    self.cardImageView.tintColor = self.theme.accentColor;
    self.tableView.separatorColor = self.theme.quaternaryBackgroundColor;
    [self.navigationItem.backBarButtonItem stp_setTheme:self.theme];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 2;
}

- (void)cancel:(__unused id)sender {
    [self.delegate paymentMethodsViewControllerDidCancel:self];
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == STPPaymentMethodCardListSection) {
        return self.paymentMethods.count;
    } else if (section == STPPaymentMethodAddCardSection) {
        return 1;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:STPPaymentMethodCellReuseIdentifier forIndexPath:indexPath];
    cell.textLabel.font = self.theme.font;
    cell.backgroundColor = self.theme.secondaryBackgroundColor;
    if (indexPath.section == STPPaymentMethodCardListSection) {
        id<STPPaymentMethod> paymentMethod = [self.paymentMethods stp_boundSafeObjectAtIndex:indexPath.row];
        cell.imageView.image = paymentMethod.image;
        BOOL selected = [paymentMethod isEqual:self.selectedPaymentMethod];
        cell.textLabel.attributedText = [self buildAttributedStringForPaymentMethod:paymentMethod selected:selected];
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if (indexPath.section == STPPaymentMethodAddCardSection) {
        cell.textLabel.textColor = [self.theme accentColor];
        cell.imageView.image = [UIImage stp_addIcon];
        cell.textLabel.text = NSLocalizedString(@"Add New Card...", nil);
    }
    return cell;
}

- (NSAttributedString *)buildAttributedStringForPaymentMethod:(id<STPPaymentMethod>)paymentMethod
                                                     selected:(BOOL)selected {
    if ([paymentMethod isKindOfClass:[STPCardPaymentMethod class]]) {
        return [self buildAttributedStringForCard:((STPCardPaymentMethod *)paymentMethod).card selected:selected];
    } else if ([paymentMethod isKindOfClass:[STPApplePayPaymentMethod class]]) {
        NSString *label = NSLocalizedString(@"Apple Pay", nil);
        UIColor *primaryColor = selected ? self.theme.accentColor : self.theme.primaryForegroundColor;
        return [[NSAttributedString alloc] initWithString:label attributes:@{NSForegroundColorAttributeName: primaryColor}];
    }
    return nil;
}

- (NSAttributedString *)buildAttributedStringForCard:(STPCard *)card selected:(BOOL)selected {
    NSString *template = NSLocalizedString(@"%@ Ending In %@", @"{card brand} ending in {last4}");
    NSString *brandString = [NSString stp_stringWithCardBrand:card.brand];
    NSString *label = [NSString stringWithFormat:template, brandString, card.last4];
    UIColor *primaryColor = selected ? self.theme.accentColor : self.theme.primaryForegroundColor;
    UIColor *secondaryColor = [primaryColor colorWithAlphaComponent:0.6f];
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:label attributes:@{
                                                                                                                       NSForegroundColorAttributeName: secondaryColor,
                                                                                                                       NSFontAttributeName: self.theme.font}];
    [attributedString addAttribute:NSForegroundColorAttributeName value:primaryColor range:[label rangeOfString:brandString]];
    [attributedString addAttribute:NSForegroundColorAttributeName value:primaryColor range:[label rangeOfString:card.last4]];
    [attributedString addAttribute:NSFontAttributeName value:self.theme.mediumFont range:[label rangeOfString:brandString]];
    [attributedString addAttribute:NSFontAttributeName value:self.theme.mediumFont range:[label rangeOfString:card.last4]];
    return [attributedString copy];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == STPPaymentMethodCardListSection) {
        id<STPPaymentMethod> paymentMethod = [self.paymentMethods stp_boundSafeObjectAtIndex:indexPath.row];
        [tableView reloadSections:[NSIndexSet indexSetWithIndex:STPPaymentMethodCardListSection] withRowAnimation:UITableViewRowAnimationFade];
        [self finishWithPaymentMethod:paymentMethod];
    } else if (indexPath.section == STPPaymentMethodAddCardSection) {
        __weak typeof(self) weakself = self;
        STPAddCardViewController *paymentCardViewController;
        // TODO
        paymentCardViewController = [[STPAddCardViewController alloc] initWithPublishableKey:self.apiClient.publishableKey requiredBillingAddressFields:STPBillingAddressFieldsNone completion:^(STPToken *token, STPErrorBlock tokenCompletion) {
            if (token && token.card) {
                [self.apiAdapter addToken:token completion:^(NSError * _Nullable error) {
                    if (error) {
                        tokenCompletion(error);
                    } else {
                        STPCardPaymentMethod *paymentMethod = [[STPCardPaymentMethod alloc] initWithCard:token.card];
                        [weakself.tableView reloadData];
                        [weakself finishWithPaymentMethod:paymentMethod];
                        tokenCompletion(nil);
                    }
                }];
            } else {
                [self.navigationController stp_popViewControllerAnimated:YES completion:^{
                    tokenCompletion(nil);
                }];
            }
        }];
        paymentCardViewController.theme = self.theme;
        NSArray *cardPaymentMethods = [self.paymentMethods filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id<STPPaymentMethod> paymentMethod, __unused NSDictionary<NSString *,id> * _Nullable bindings) {
            return [paymentMethod isKindOfClass:[STPCardPaymentMethod class]];
        }]];
        // Disable SMS autofill if we already have a card on file
        paymentCardViewController.smsAutofillDisabled = cardPaymentMethods.count > 0;
        [self.navigationController pushViewController:paymentCardViewController animated:YES];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

//- (BOOL)tableView:(__unused UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
//    if (indexPath.section == STPPaymentMethodCardListSection) {
//        id<STPPaymentMethod> paymentMethod = [self.paymentMethods stp_boundSafeObjectAtIndex:indexPath.row];
//        return [paymentMethod isKindOfClass:[STPCardPaymentMethod class]];
//    }
//    return NO;
//}

//- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
//    if (editingStyle == UITableViewCellEditingStyleDelete) {
//        id<STPPaymentMethod> paymentMethod = [self.paymentMethods stp_boundSafeObjectAtIndex:indexPath.row];
//        BOOL wasSelected = [paymentMethod isEqual:self.selectedPaymentMethod];
//        [self.paymentContext deletePaymentMethod:paymentMethod];
//        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
//        NSInteger index = [self.paymentContext.paymentMethods indexOfObject:self.paymentContext.selectedPaymentMethod];
//        if (wasSelected && index != NSNotFound) {
//            NSIndexPath *selectedIndexPath = [NSIndexPath indexPathForRow:index inSection:STPPaymentMethodCardListSection];
//            [self.tableView reloadRowsAtIndexPaths:@[selectedIndexPath] withRowAnimation:UITableViewRowAnimationFade];
//        }
//    }
//}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL topRow = (indexPath.row == 0);
    BOOL bottomRow = ([self tableView:tableView numberOfRowsInSection:indexPath.section] - 1 == indexPath.row);
    [cell stp_setBorderColor:self.theme.tertiaryBackgroundColor];
    [cell stp_setTopBorderHidden:!topRow];
    [cell stp_setBottomBorderHidden:!bottomRow];
}

- (void)finishWithPaymentMethod:(id<STPPaymentMethod>)paymentMethod {
    [self.delegate paymentMethodsViewController:self didSelectPaymentMethod:paymentMethod];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if ([self tableView:tableView numberOfRowsInSection:section] == 0) {
        return 0.01f;
    }
    return 27.0f;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForHeaderInSection:(__unused NSInteger)section {
    return 0.01f;
}

@end

@implementation STPPaymentMethodsViewController (Private)

- (instancetype)initWithAPIClient:(STPAPIClient *)apiClient
                       APIAdapter:(id<STPBackendAPIAdapter>)apiAdapter
                   loadingPromise:(STPPromise<STPPaymentMethodTuple *> *)loadingPromise {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _apiClient = apiClient;
        _apiAdapter = apiAdapter;
        _loadingPromise = loadingPromise;
        __weak typeof(self) weakself = self;
        [loadingPromise onSuccess:^(STPPaymentMethodTuple *tuple) {
            weakself.paymentMethods = tuple.paymentMethods;
            weakself.selectedPaymentMethod = tuple.selectedPaymentMethod;
        }];
    }
    return self;
}

@end