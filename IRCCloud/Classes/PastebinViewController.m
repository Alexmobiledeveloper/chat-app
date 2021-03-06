//
//  PastebinViewController.m
//
//  Copyright (C) 2013 IRCCloud, Ltd.
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <MobileCoreServices/UTCoreTypes.h>
#import <SafariServices/SafariServices.h>
#import <Twitter/Twitter.h>
#import "PastebinViewController.h"
#import "NetworkConnection.h"
#import "OpenInChromeController.h"
#import "OpenInFirefoxControllerObjC.h"
#import "AppDelegate.h"
#import "PastebinEditorViewController.h"
#import "UIColor+IRCCloud.h"

@implementation PastebinViewController

-(void)setUrl:(NSURL *)url {
    _url = url.absoluteString;
    
    if([_url rangeOfString:@"?"].location != NSNotFound) {
        NSString *query = [_url substringFromIndex:[_url rangeOfString:@"?"].location + 1];
        NSArray *args = [query componentsSeparatedByString:@"&"];
        for(NSString *arg in args) {
            NSArray *pair = [arg componentsSeparatedByString:@"="];
            
            if([[pair objectAtIndex:0] isEqualToString:@"id"])
                _pasteID = [pair objectAtIndex:1];
            else if([[pair objectAtIndex:0] isEqualToString:@"own_paste"])
                _ownPaste = [[pair objectAtIndex:1] isEqualToString:@"1"];
        }
        
        _url = [_url substringToIndex:[_url rangeOfString:@"?"].location];
    }
}


- (NSArray<id<UIPreviewActionItem>> *)previewActionItems {
    NSURL *url = [NSURL URLWithString:_url];
    
    return @[
                              [UIPreviewAction actionWithTitle:@"Copy URL" style:UIPreviewActionStyleDefault handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                  UIPasteboard *pb = [UIPasteboard generalPasteboard];
                                  [pb setValue:_url forPasteboardType:(NSString *)kUTTypeUTF8PlainText];
                              }],
                              [UIPreviewAction actionWithTitle:@"Share" style:UIPreviewActionStyleDefault handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                  UIApplication *app = [UIApplication sharedApplication];
                                  AppDelegate *appDelegate = (AppDelegate *)app.delegate;
                                  MainViewController *mainViewController = [appDelegate mainViewController];
                                  
                                  UIActivityViewController *activityController = [URLHandler activityControllerForItems:@[url] type:@"Pastebin"];
                                  activityController.popoverPresentationController.sourceView = mainViewController.slidingViewController.view;
                                  [mainViewController.slidingViewController presentViewController:activityController animated:YES completion:nil];
                              }],
                              [UIPreviewAction actionWithTitle:@"Open in Browser" style:UIPreviewActionStyleDefault handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
                                  if([[[NSUserDefaults standardUserDefaults] objectForKey:@"browser"] isEqualToString:@"Chrome"] && [[OpenInChromeController sharedInstance] openInChrome:url
                                                                                                                                                                          withCallbackURL:[NSURL URLWithString:
#ifdef ENTERPRISE
                                                                                                                                                                                           @"irccloud-enterprise://"
#else
                                                                                                                                                                                           @"irccloud://"
#endif
                                                                                                                                                                                           ]
                                                                                                                                                                             createNewTab:NO])
                                      return;
                                  else if([[[NSUserDefaults standardUserDefaults] objectForKey:@"browser"] isEqualToString:@"Firefox"] && [[OpenInFirefoxControllerObjC sharedInstance] openInFirefox:url])
                                      return;
                                  else
                                      [[UIApplication sharedApplication] openURL:url];
                              }]
                              ];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_activity startAnimating];
    _lineNumbers.enabled = NO;
    _lineNumbers.on = YES;
    [self _fetch];
    [Answers logContentViewWithName:nil contentType:@"Pastebin" contentId:nil customAttributes:nil];
    [self didMoveToParentViewController:nil];
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_doneButtonPressed)];
    _chrome = [[OpenInChromeController alloc] init];
    self.navigationController.navigationBar.clipsToBounds = YES;
    self.automaticallyAdjustsScrollViewInsets = NO;

    _lineNumbers = [[UISwitch alloc] initWithFrame:CGRectZero];
    _lineNumbers.on = YES;
    [_lineNumbers addTarget:self action:@selector(_toggleLineNumbers) forControlEvents:UIControlEventValueChanged];
    
    if(_ownPaste) {
        [_toolbar setItems:@[[[UIBarButtonItem alloc] initWithTitle:@"Line Numbers" style:UIBarButtonItemStylePlain target:self action:@selector(_toggleLineNumbersSwitch)],
                             [[UIBarButtonItem alloc] initWithCustomView:_lineNumbers],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(_editPaste)],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(_removePaste)],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareButtonPressed:)]
                             ]];
    } else {
        [_toolbar setItems:@[[[UIBarButtonItem alloc] initWithTitle:@"Line Numbers" style:UIBarButtonItemStylePlain target:self action:@selector(_toggleLineNumbersSwitch)],
                             [[UIBarButtonItem alloc] initWithCustomView:_lineNumbers],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
                             [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareButtonPressed:)]
                             ]];
        
    }
    _lineNumbers.enabled = NO;
    [_lineNumbers sizeToFit];
    
    _webView.opaque = NO;
    _webView.backgroundColor = [UIColor contentBackgroundColor];
    _webView.scrollView.scrollsToTop = YES;
    
    self.view.backgroundColor = [UIColor contentBackgroundColor];
    
    if([UIColor isDarkTheme]) {
        self.navigationController.view.backgroundColor = [UIColor navBarColor];
        _activity.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhite;
        [_toolbar setBackgroundImage:[UIColor navBarBackgroundImage] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
        [_toolbar setTintColor:[UIColor navBarSubheadingColor]];
    } else {
        self.navigationController.view.backgroundColor = [UIColor navBarColor];
        _activity.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
    }
}

-(void)didMoveToParentViewController:(UIViewController *)parent {
    CGRect frame = _webView.frame;
    if(self.navigationController.navigationBarHidden) {
        _toolbar.hidden = YES;
        frame.size.height = self.view.frame.size.height - _webView.frame.origin.y;
    } else {
        _toolbar.hidden = NO;
        frame.size.height = self.view.frame.size.height - _webView.frame.origin.y - _toolbar.frame.size.height;
    }
    _webView.frame = frame;
}

-(void)_fetch {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSURL *url = [NSURL URLWithString:[_url stringByAppendingFormat:@"?mobile=ios&version=%@&theme=%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"], [[NSUserDefaults standardUserDefaults] objectForKey:@"theme"]]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
    [request setHTTPShouldHandleCookies:NO];
    [request setValue:[NSString stringWithFormat:@"session=%@", [NetworkConnection sharedInstance].session] forHTTPHeaderField:@"Cookie"];
    
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:[NSHTTPCookie cookieWithProperties:@{
                                                                                                  NSHTTPCookieName:@"session",
                                                                                                  NSHTTPCookieValue:[NetworkConnection sharedInstance].session,
                                                                                                  NSHTTPCookieDomain:url.host,
                                                                                                  NSHTTPCookiePath:@"/",
                                                                                                  NSHTTPCookieVersion:@"0",
                                                                                                  }]];
    [_webView loadRequest:request];
}

-(void)_doneButtonPressed {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

-(void)_toggleLineNumbers {
    if(_lineNumbers.enabled)
        [_webView stringByEvaluatingJavaScriptFromString:@"window.PASTEVIEW.doToggleLines()"];
}

-(void)_toggleLineNumbersSwitch {
    if(_lineNumbers.enabled) {
        [_lineNumbers setOn:!_lineNumbers.on animated:YES];
        [self _toggleLineNumbers];
    }
}

-(void)_removePaste {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Snippet" message:@"Are you sure you want to delete this text snippet?" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Delete", nil];
    [alert show];
}

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if([[alertView buttonTitleAtIndex:buttonIndex] isEqualToString:@"Delete"]) {
        [[NetworkConnection sharedInstance] deletePaste:_pasteID];
        if(self.navigationController.viewControllers.count == 1)
            [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        else
            [self.navigationController popViewControllerAnimated:YES];
    }
}

-(void)_editPaste {
    [self.navigationController pushViewController:[[PastebinEditorViewController alloc] initWithPasteID:_pasteID] animated:YES];
    [_webView loadHTMLString:@"" baseURL:nil];
}

-(IBAction)shareButtonPressed:(id)sender {
    if(NSClassFromString(@"UIActivityViewController")) {
        UIActivityViewController *activityController = [URLHandler activityControllerForItems:@[[NSURL URLWithString:_url]] type:@"Pastebin"];
        activityController.popoverPresentationController.delegate = self;
        activityController.popoverPresentationController.barButtonItem = sender;
        [self presentViewController:activityController animated:YES completion:nil];
    }
}

-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if(([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) || ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled))
        return;
    NSLog(@"Error: %@", error);
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [_activity stopAnimating];
}

-(void)webViewDidStartLoad:(UIWebView *)webView {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
}

-(void)webViewDidFinishLoad:(UIWebView *)webView {
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

-(BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if([request.URL.scheme isEqualToString:@"hide-spinner"]) {
        [_activity stopAnimating];
        _lineNumbers.enabled = YES;
        return NO;
    }
    return YES;
}

-(void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

@end
