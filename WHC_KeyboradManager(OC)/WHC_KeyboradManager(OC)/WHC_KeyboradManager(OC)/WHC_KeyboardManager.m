//
//  WHC_KeyboardManager.m
//  WHC_KeyboardManager(OC)
//
//  Created by WHC on 16/11/20.
//  Copyright © 2016年 WHC. All rights reserved.
//
//  Github <https://github.com/netyouli/WHC_KeyboardManager>

//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "WHC_KeyboardManager.h"
#import "NSObject+WHC_Extension.h"
#import <objc/runtime.h>


/// 获取下一个编辑框视图的通知
const NSString * WHC_KBM_NextFieldView = @"GetNextFieldViewNotification";
/// 获取当前编辑框视图的通知
const NSString * WHC_KBM_CurrentFieldView = @"GetCurrentFieldViewNotification";
/// 获取上一个编辑框视图的通知
const NSString * WHC_KBM_FrontFieldView = @"GetFrontFieldViewNotification";
/// 滚动视图滚动keypath
const static NSString * kWHC_KBM_ContentOffset = @"contentOffset";

const static NSString * WHCObserve = @"kWHCObserve";

@interface WHC_KBMConfiguration ()

/// 获取移动视图的偏移回调块
@property (nonatomic, copy) CGFloat (^offsetBlock)(UIView * field);
/// 获取移动视图回调
@property (nonatomic, copy) UIView* (^offsetViewBlock)(UIView * field);
/// 动画完成block回调
@property(nonatomic, copy) dispatch_block_t keyboardAnimationCompletionBlock;
// 动画开始block 回调
@property(nonatomic, copy) void (^keyboardAnimationBeginingBlock)(BOOL keyboardHidden);
@end

@implementation WHC_KBMConfiguration

- (void)dealloc {
    self.offsetBlock = nil;
    self.offsetViewBlock = nil;
    self.keyboardAnimationCompletionBlock = nil;
    self.keyboardAnimationBeginingBlock = nil;
    
//    NSLog(@">>>>> %s  dealloc ",__func__);
}

- (instancetype)init {
    self = [super init];
    _headerView = WHC_KeyboardHeaderView.new;
    return self;
}

- (void)setEnableHeader:(BOOL)enableHeader {
    _enableHeader = enableHeader;
    if (_enableHeader) {
        if (_headerView == nil) {
            _headerView = WHC_KeyboardHeaderView.new;
        }
    }else {
        _headerView = nil;
    }
}

- (void)setOffset:(CGFloat (^)(UIView * field))block {
    self.offsetBlock = block;
}

- (void)setOffsetView:(UIView * (^)(UIView * field))block {
    self.offsetViewBlock = block;
}

- (void)keyoboardAnimationCompletionBlock:(dispatch_block_t)block {
    self.keyboardAnimationCompletionBlock = block;
}

- (void)keyoboardAnimationBeginingBlock:(void (^)(BOOL keyboardHidden))block {
    self.keyboardAnimationBeginingBlock = block;
}

@end

/// 初始化标示
const static CGFloat kNotInitValue = -888888.88;

@interface WHC_KeyboardManager ()
/// 监视控制器和配置集合
@property (nonatomic, strong) NSMutableDictionary<NSNumber *,WHC_KBMConfiguration *> * KeyboardConfigurations;
/// 当前的输入视图(UITextView/UITextField)
@property (nonatomic, strong) UIView * currentField;
/// 上一个输入视图
@property (nonatomic, strong) UIView * frontField;
/// 下一个输入视图
@property (nonatomic, strong) UIView * nextField;
/// 要监视处理的控制器集合
@property (nonatomic, strong) NSMutableArray <NSString *> * monitorViewControllers;
/// 当前监视处理的控制器
@property (nonatomic, weak) UIViewController * currentMonitorViewController;
/// 设置移动的视图动画周期
@property (nonatomic, assign) NSTimeInterval moveViewAnimationDuration;
/// 键盘出现的动画周期
@property (nonatomic, assign) NSTimeInterval keyboardDuration;
/// 存储键盘的frame
@property (nonatomic, assign) CGRect keyboardFrame;
/// 是否已经显示了header
@property (nonatomic, assign) BOOL didShowHeader;
/// 是否已经移除了键盘监听
@property (nonatomic, assign) BOOL didRemoveKBObserve;
/// 保存moveView初始y
@property (nonatomic, assign) CGFloat initMoveViewY;

@end

@implementation WHC_KeyboardManager

+ (instancetype)share {
    static dispatch_once_t onceToken;
    static WHC_KeyboardManager * kbManager = nil;
    dispatch_once(&onceToken, ^{
        kbManager = WHC_KeyboardManager.new;
    });
    return kbManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _initMoveViewY = kNotInitValue;
        _KeyboardConfigurations = [NSMutableDictionary dictionary];
//        _monitorViewControllers = [NSMutableArray array];
        _moveViewAnimationDuration = 0.5;
        _moveDidAnimation = YES;
        [self addKeyboardMonitor];
    }
    return self;
}

- (void)dealloc {
    [self removeKeyboardObserver];
}

#pragma mark - 私有方法 -

/// 添加键盘监听
- (void)addKeyboardMonitor {
    NSNotificationCenter * nCenter = [NSNotificationCenter defaultCenter];
    
    [nCenter addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [nCenter addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    [nCenter addObserver:self selector:@selector(myTextFieldDidBeginEditing:) name:UITextFieldTextDidBeginEditingNotification object:nil];
    [nCenter addObserver:self selector:@selector(myTextFieldDidEndEditing:) name:UITextFieldTextDidEndEditingNotification object:nil];
    [nCenter addObserver:self selector:@selector(myTextFieldDidBeginEditing:) name:UITextViewTextDidBeginEditingNotification object:nil];
    [nCenter addObserver:self selector:@selector(myTextFieldDidEndEditing:) name:UITextViewTextDidEndEditingNotification object:nil];
}

/// 检查是否是系统的私有滚动类
- (BOOL)checkIsPrivateContainerClassWithView:(UIView *)view {
    static Class UITableViewCellScrollViewClass = nil;
    static Class UITableViewWrapperViewClass = nil;
    static Class UIQueuingScrollViewClass = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UITableViewCellScrollViewClass = NSClassFromString(@"UITableViewCellScrollView");
        UITableViewWrapperViewClass = NSClassFromString(@"UITableViewWrapperView");
        UIQueuingScrollViewClass = NSClassFromString(@"_UIQueuingScrollView");
    });
    
    return !(([view isKindOfClass:UITableViewWrapperViewClass] == NO) &&
             ([view isKindOfClass:UITableViewCellScrollViewClass] == NO) &&
             ([view isKindOfClass:UIQueuingScrollViewClass] == NO));
}

/// 检查是否系统的私有输入类
- (BOOL)checkIsPrivateInputClassWithView:(UIView *)view {
    static Class UISearchBarTextFieldClass = nil;
    static Class UIAlertSheetTextFieldClass = nil;
    static Class UIAlertSheetTextFieldClass_iOS8 = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UISearchBarTextFieldClass = NSClassFromString(@"UISearchBarTextField");
        UIAlertSheetTextFieldClass = NSClassFromString(@"UIAlertSheetTextField");
        UIAlertSheetTextFieldClass_iOS8 = NSClassFromString(@"_UIAlertControllerTextField");
    });
    return !(([view isKindOfClass:UISearchBarTextFieldClass] == NO) &&
             ([view isKindOfClass:UIAlertSheetTextFieldClass] == NO) &&
             ([view isKindOfClass:UIAlertSheetTextFieldClass_iOS8] == NO));
}

/// 动态扫描前后field

- (NSArray <UIView *> *)startScan:(UIView *)view {
    NSMutableArray <UIView *> * subFields = [NSMutableArray array];
    if (view.userInteractionEnabled && view.alpha != 0 && !view.hidden) {
        if ([view isKindOfClass:[UITextView class]]) {
            if (![subFields containsObject:view] && ((UITextView *)view).editable) {
                [subFields addObject:view];
            }
        }else if ([view isKindOfClass:[UITextField class]]) {
            if (![subFields containsObject:view] && ((UITextField *)view).enabled && ![self checkIsPrivateInputClassWithView:view]) {
                [subFields addObject:view];
            }
        }else if (view.subviews.count != 0) {
            [view.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull subView, NSUInteger idx, BOOL * _Nonnull stop) {
                [subFields addObjectsFromArray:[self startScan:subView]];
            }];
        }
    }
    return subFields;
}

- (void)scanFrontNextField {
    NSArray <UIView *> * fields = [self startScan:[self getCurrentOffsetView]];
    fields = [fields sortedArrayUsingComparator:^NSComparisonResult(UIView *  _Nonnull field1, UIView *  _Nonnull field2) {
        CGRect fieldConvertFrame1 = [field1 convertRect:field1.bounds toView:_currentMonitorViewController.view];
        CGRect fieldConvertFrame2 = [field2 convertRect:field2.bounds toView:_currentMonitorViewController.view];
        CGFloat field1X = fieldConvertFrame1.origin.x;
        CGFloat field1Y = fieldConvertFrame1.origin.y;
        CGFloat field2X = fieldConvertFrame2.origin.x;
        CGFloat field2Y = fieldConvertFrame2.origin.y;
        if (field1Y < field2Y)      return NSOrderedAscending;
        else if (field1Y > field2Y) return NSOrderedDescending;
        else if (field1X < field2X) return NSOrderedAscending;
        else if (field1X > field2X) return NSOrderedDescending;
        else return NSOrderedSame;
    }];
    _frontField = nil, _nextField = nil;
    NSUInteger index = [fields indexOfObject:_currentField];
    if (index != NSNotFound) {
        if (index > 0) {
            _frontField = fields[index - 1];
        }
        if (index < fields.count - 1) {
            _nextField = fields[index + 1];
        }
    }
}

/// 动态获取偏移视图
- (UIView *)getCurrentOffsetView {
    WHC_KBMConfiguration * config = [self getCurrentConfig];
    if (config && config.offsetViewBlock) {
        UIView * offsetView = config.offsetViewBlock(_currentField);
        if (offsetView) return offsetView;
    }
    if (_currentField) {
        UIView * superView = _currentField;
        UIView * tempSuperview = superView.superview;
        while (tempSuperview) {
            if ([tempSuperview isKindOfClass:[UIScrollView class]] ||
                [tempSuperview isKindOfClass:[UITableView class]] ||
                [tempSuperview isKindOfClass:[UICollectionView class]]) {
                if ([tempSuperview isKindOfClass:[UITextView class]] == NO && ![self checkIsPrivateContainerClassWithView:tempSuperview]) {
                    if (((UIScrollView *)tempSuperview).contentSize.height > tempSuperview.frame.size.height && ((UIScrollView *)tempSuperview).isScrollEnabled ) {
                        return tempSuperview;
                    }
                }
            }
            if ([NSStringFromClass(tempSuperview.classForCoder) isEqualToString:@"UIViewControllerWrapperView"]) {
                break;
            }else {
                tempSuperview = tempSuperview.superview;
            }
        }
        return (_currentMonitorViewController != nil && _currentMonitorViewController.view != nil) ? _currentMonitorViewController.view : tempSuperview;
    }
    return nil;
}

/// 自动移除键盘头
- (void)autoRemoveHeader {
    [_KeyboardConfigurations enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, WHC_KBMConfiguration * _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj.headerView) {
            [obj.headerView removeFromSuperview];
        }
    }];
    _didShowHeader = NO;
}

/// 获取当前配置
- (WHC_KBMConfiguration *)getCurrentConfig {
    WHC_KBMConfiguration * config = nil;
    UIViewController * currentVC = [self whc_CurrentViewController];
    if (currentVC) {
        WHC_KBMConfiguration * tmpConfig = _KeyboardConfigurations[@(currentVC.hash)];
        if (tmpConfig) {
            config = tmpConfig;
        }
    }
    return config;
}

/// 动态更新键盘头部视图
- (void)updateHeaderViewWithComplete:(void(^)(void))complete {
    if (_keyboardFrame.size.width == 0) {
        [self autoRemoveHeader];
        if (complete) {
            complete();
        }
    }else {
        UIView * headerView = nil;
        WHC_KBMConfiguration * config = [self getCurrentConfig];
        if (config) {
            headerView = config.headerView;
        }
        if (headerView) {
            void (^addHeaderViewConstraint)(UIView * headerView) = ^(UIView * headerView) {
                [headerView.superview addConstraint:[NSLayoutConstraint constraintWithItem:headerView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:headerView.superview attribute:NSLayoutAttributeLeft multiplier:1 constant:0]];
                [headerView.superview addConstraint:[NSLayoutConstraint constraintWithItem:headerView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:headerView.superview attribute:NSLayoutAttributeRight multiplier:1 constant:0]];
                [headerView addConstraint:[NSLayoutConstraint constraintWithItem:headerView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:44]];
                [headerView.superview addConstraint:[NSLayoutConstraint constraintWithItem:headerView attribute:NSLayoutAttributeLastBaseline relatedBy:NSLayoutRelationEqual toItem:headerView.superview attribute:NSLayoutAttributeLastBaseline multiplier:1 constant:-_keyboardFrame.size.height]];
            };
            if (headerView.superview == nil) {
                if (_currentMonitorViewController.view.window) {
                    [_currentMonitorViewController.view.window addSubview:headerView];
                }
                if (headerView.translatesAutoresizingMaskIntoConstraints) {
                    headerView.translatesAutoresizingMaskIntoConstraints = NO;
                }
                addHeaderViewConstraint(headerView);
            }else {
                if (!headerView.translatesAutoresizingMaskIntoConstraints) {
                    [headerView.superview.constraints enumerateObjectsUsingBlock:^(__kindof NSLayoutConstraint * _Nonnull constraint, NSUInteger idx, BOOL * _Nonnull stop) {
                        if (constraint.firstItem == headerView) {
                            [headerView.superview removeConstraint:constraint];
                        }
                    }];
                    addHeaderViewConstraint(headerView);
                }
            }
            if (!_didShowHeader) {
                headerView.alpha = 0;
                NSTimeInterval duration = _keyboardDuration == 0 ? 0.25 : _keyboardDuration;
                [UIView animateWithDuration:_moveViewAnimationDuration delay:duration options:UIViewAnimationOptionCurveEaseOut animations:^{
                    headerView.alpha = 0.9;
                } completion:^(BOOL finished) {
                    _didShowHeader = YES;
                    if (complete) {
                        complete();
                    }
                }];
            }
        }
    }
}

/// 处理键盘出现时自动调整当前UI(输入视图不被遮挡)
- (void)handleKeyboardDidShowToAdjust {
    if (!_moveDidAnimation) {
        return;
    }
    
    WHC_KBMConfiguration * _KeyboardConfiguration = [self getCurrentConfig];
    UIView * headerView = nil;
    if (_KeyboardConfiguration) {
        headerView = _KeyboardConfiguration.headerView;
    }
    CGFloat(^offsetBlock)(UIView * field) = _KeyboardConfiguration != nil ? _KeyboardConfiguration.offsetBlock : nil;
    if (_keyboardFrame.size.height != 0 && _currentField != nil && ![self checkIsPrivateInputClassWithView:_currentField]) {
        UIView * moveView = [self getCurrentOffsetView];
        UIScrollView * moveScrollView = nil;
        if ([moveView isKindOfClass:[UITableView class]] ||
            [moveView isKindOfClass:[UIScrollView class]] ||
            [moveView isKindOfClass:[UICollectionView class]]) {
            moveScrollView = (UIScrollView *)moveView;
            BOOL didObs = NO;
            NSNumber * obs = objc_getAssociatedObject(moveScrollView, &WHCObserve);
            if (obs && obs.boolValue) {
                didObs = YES;
            }
            if (!obs) {
                objc_setAssociatedObject(moveScrollView, &WHCObserve, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [moveScrollView addObserver:self forKeyPath:(NSString *)kWHC_KBM_ContentOffset options:NSKeyValueObservingOptionNew context:nil];
            }
        }else {
            if (_initMoveViewY == kNotInitValue) {
                _initMoveViewY = moveView.frame.origin.y;
            }
        }
        
        UIView * convertView = moveScrollView == nil ? _currentMonitorViewController.view : _currentMonitorViewController.view.window;
        CGRect convertRect = [_currentField convertRect:_currentField.bounds toView:convertView];
        CGFloat defaultOffset = 0;
        if (convertView.frame.size.height < [UIScreen mainScreen].bounds.size.height && _currentMonitorViewController.navigationController) {
            if (!_currentMonitorViewController.navigationController.isNavigationBarHidden && _currentMonitorViewController.edgesForExtendedLayout == UIRectEdgeAll) {
                defaultOffset = CGRectGetMaxY(_currentMonitorViewController.navigationController.navigationBar.frame);
            }
            convertRect.origin.y += defaultOffset;
        }
        if (headerView) {
            [headerView layoutIfNeeded];
        }
        CGFloat yOffset = CGRectGetMaxY(convertRect) - CGRectGetMinY(_keyboardFrame);
        CGFloat headerHeight = headerView != nil ? headerView.frame.size.height : 0;
        CGFloat moveOffset = offsetBlock == nil ? headerHeight : offsetBlock(_currentField) + headerHeight;
        if (offsetBlock == nil && headerView == nil) {
            if (_nextField) {
                CGRect nextFrame = [_nextField convertRect:_nextField.bounds toView:convertView];
                moveOffset += CGRectGetMaxY(nextFrame) - CGRectGetMaxY(convertRect);
            }
        }
        if (moveScrollView) {
            CGFloat sumOffsetY = moveScrollView.contentOffset.y + moveOffset + yOffset;
            sumOffsetY = MAX(sumOffsetY, -moveScrollView.contentInset.top);
            [UIView animateWithDuration:_moveViewAnimationDuration animations:^{
                moveScrollView.contentOffset = CGPointMake(moveScrollView.contentOffset.x, sumOffsetY);
            }];
        }else {
            CGFloat sumOffsetY = -(moveOffset + yOffset);
            sumOffsetY = MIN(_initMoveViewY, sumOffsetY);
            CGRect moveViewFrame = moveView.frame;
            moveViewFrame.origin.y = sumOffsetY;
            _moveDidAnimation = NO;
            
            [UIView animateWithDuration:_moveViewAnimationDuration animations:^{
                moveView.frame = moveViewFrame;
                
            } completion:^(BOOL finished) {
                if (finished && moveView.frame.origin.y != moveViewFrame.origin.y) {
                    moveView.frame = moveViewFrame;
                    [moveView.superview layoutIfNeeded];
                }
                
                //TODO:动画完成block
                WHC_KBMConfiguration *config =  [_KeyboardConfigurations objectForKey:@(_currentMonitorViewController.hash)];
                if (config.keyboardAnimationCompletionBlock) {
                    config.keyboardAnimationCompletionBlock();
                }
                
                //TODO: 动画完成动画延迟，防止发生抖动
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                      self->_moveDidAnimation = YES;
                });
            }];
        }
    }
}

- (void)setCurrentMonitorViewController {
    if (_KeyboardConfigurations.count > 0) {
        UIViewController * topViewController = [self whc_CurrentViewController];
        _currentMonitorViewController = nil;
        if (topViewController != nil && [_KeyboardConfigurations objectForKey:@(topViewController.hash)]) {
            _currentMonitorViewController = topViewController;
        }
    }
}

#pragma mark - 公开Api -
- (WHC_KBMConfiguration *)addMonitorViewController:(UIViewController *)vc {
    WHC_KBMConfiguration * configuration = [WHC_KBMConfiguration new];
    _KeyboardConfigurations[@(vc.hash)] = configuration;
//    if (![_monitorViewControllers containsObject:vc.description]) {
//        [_monitorViewControllers addObject:vc.description];
//    }
    if (_didRemoveKBObserve) {
        [self addKeyboardMonitor];
        _didRemoveKBObserve = NO;
    }
    return configuration;
}

- (void)removeMonitorViewController:(UIViewController *)vc {
    if (vc != nil) {
        [_KeyboardConfigurations removeObjectForKey:@(vc.hash)];
        NSString *str = [NSString stringWithFormat:@"%zd",vc.hash];
        if ([_monitorViewControllers containsObject:str]) {
            [_monitorViewControllers removeObject:str];
        }
    }
}

- (void)removeKeyboardObserver {
    [_KeyboardConfigurations removeAllObjects];
//    [_monitorViewControllers removeAllObjects];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _didRemoveKBObserve = YES;
}

//MARK: - 发送通知 -
- (void)sendFieldViewNotify {
    WHC_KBMConfiguration * _KeyboardConfiguration = [self getCurrentConfig];
    if (_KeyboardConfiguration && _KeyboardConfiguration.headerView) {
        NSNotificationCenter * nCenter = [NSNotificationCenter defaultCenter];
        [nCenter postNotificationName:(NSString *)WHC_KBM_CurrentFieldView object:_currentField];
        [nCenter postNotificationName:(NSString *)WHC_KBM_FrontFieldView object:_frontField];
        [nCenter postNotificationName:(NSString *)WHC_KBM_NextFieldView object:_nextField];
    }
}

#pragma mark - 键盘监听处理 -

- (void)keyboardWillShow:(NSNotification *)notify {
    
    
    
//     UIView * fieldView = notify.object;
  
    if (_currentField == nil) {
        [self setCurrentMonitorViewController];
    }
    if (_currentMonitorViewController == nil) return;
    
    
    //TODO :动画开始block
    WHC_KBMConfiguration *config =  [_KeyboardConfigurations objectForKey:@(_currentMonitorViewController.hash)];
    if (config.keyboardAnimationBeginingBlock) {
        config.keyboardAnimationBeginingBlock(NO);
    }
    
    
    NSDictionary * userInfo = notify.userInfo;
    _keyboardFrame = ((NSValue *)userInfo[UIKeyboardFrameEndUserInfoKey]).CGRectValue;
    _keyboardDuration = ((NSNumber *)userInfo[UIKeyboardAnimationDurationUserInfoKey]).doubleValue;
  
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_keyboardDuration * .6f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [self updateHeaderViewWithComplete:nil];
          [self handleKeyboardDidShowToAdjust];
    });
}

- (void)keyboardWillHide:(NSNotification *)notify {
  
    //TODO :动画开始block
    WHC_KBMConfiguration *config =  [_KeyboardConfigurations objectForKey:@(_currentMonitorViewController.hash)];
    if (config.keyboardAnimationBeginingBlock) {
        config.keyboardAnimationBeginingBlock(YES);
    }
    
    _keyboardFrame.size.width = 0;
    _keyboardDuration = 0;
    [self updateHeaderViewWithComplete:nil];
    _keyboardFrame = CGRectZero;
    if (_currentField && [self checkIsPrivateInputClassWithView:_currentField]) return;
    UIView * moveView = [self getCurrentOffsetView];
    if ([moveView isKindOfClass:[UITableView class]] ||
        [moveView isKindOfClass:[UIScrollView class]] ||
        [moveView isKindOfClass:[UICollectionView class]]) {
        UIScrollView * scrollMoveView = (UIScrollView *)moveView;
        if (scrollMoveView) {
            NSNumber * obs = objc_getAssociatedObject(scrollMoveView, &WHCObserve);
            if (obs && obs.boolValue) {
                objc_setAssociatedObject(scrollMoveView, &WHCObserve, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [scrollMoveView removeObserver:self forKeyPath:(NSString *)kWHC_KBM_ContentOffset];
            }
            [UIView animateWithDuration:_moveViewAnimationDuration animations:^{
                if (scrollMoveView.contentOffset.y < -scrollMoveView.contentInset.top) {
                    scrollMoveView.contentOffset = CGPointMake(scrollMoveView.contentOffset.x, -scrollMoveView.contentInset.top);
                }else if (scrollMoveView.contentOffset.y > scrollMoveView.contentSize.height - scrollMoveView.bounds.size.height + scrollMoveView.contentInset.bottom) {
                    if (scrollMoveView.contentSize.height == 0) {
                        scrollMoveView.contentOffset = CGPointMake(scrollMoveView.contentOffset.x, -scrollMoveView.contentInset.top);
                    }else {
                        scrollMoveView.contentOffset = CGPointMake(scrollMoveView.contentOffset.x, scrollMoveView.contentSize.height - scrollMoveView.bounds.size.height + scrollMoveView.contentInset.bottom);
                    }
                }
            }];
        }
    }else {
        CGRect moveViewFrame = moveView.frame;
        if (_initMoveViewY != kNotInitValue) {
            moveViewFrame.origin.y = _initMoveViewY;
        }
        _initMoveViewY = kNotInitValue;
        /**** Give up the following method ***/
        /*
         if (_currentMonitorViewController.view == moveView && _currentMonitorViewController.navigationController != nil && _currentMonitorViewController.edgesForExtendedLayout == UIRectEdgeNone && !_currentMonitorViewController.navigationController.navigationBarHidden) {
         moveViewFrame.origin.y = _currentMonitorViewController.navigationController.navigationBar.bounds.size.height;
         }else {
         moveViewFrame.origin.y = 0;
         }*/
        [UIView animateWithDuration:_moveViewAnimationDuration animations:^{
            moveView.frame = moveViewFrame;
            [moveView.superview layoutIfNeeded];
        }];
        
        //TODO:动画完成block
        WHC_KBMConfiguration *config =  [_KeyboardConfigurations objectForKey:@(_currentMonitorViewController.hash)];
        if (config.keyboardAnimationCompletionBlock) {
            config.keyboardAnimationCompletionBlock();
        }
        
    }
}

#pragma mark - 滚动监听 -
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (_currentMonitorViewController == nil) return;
    if (keyPath && [keyPath isEqualToString:(NSString *)kWHC_KBM_ContentOffset] && _currentField) {
        UIScrollView * scrollView = object;
        if (scrollView != nil && (scrollView.dragging || scrollView.decelerating)) {
            CGRect convertRect = [_currentField convertRect:_currentField.bounds toView:_currentMonitorViewController.view.window];
            CGFloat yOffset = CGRectGetMaxY(convertRect) - CGRectGetMinY(_keyboardFrame);
            if (yOffset > 0 || CGRectGetMinY(convertRect) < 0) {
                if ([_currentField isKindOfClass:[UITextView class]]) {
                    [((UITextView *)_currentField) resignFirstResponder];
                }else if ([_currentField isKindOfClass:[UITextField class]]) {
                    [((UITextField *)_currentField) resignFirstResponder];
                }else {
                    [_currentField endEditing:YES];
                }
            }
        }
    }
}

#pragma mark - 编辑通知 -

- (void)myTextFieldDidBeginEditing:(NSNotification *)notify {
    [self setCurrentMonitorViewController];
    if (_currentMonitorViewController) {
        _currentField = notify.object;
        [self scanFrontNextField];
        [self sendFieldViewNotify];
        [self handleKeyboardDidShowToAdjust];
    }
}

- (void)myTextFieldDidEndEditing:(NSNotification *)notify {
    UIView * fieldView = notify.object;
    if (fieldView == _currentField) {
        _currentField = nil;
        _nextField = nil;
        _frontField = nil;
        _currentMonitorViewController = nil;
    }
}

@end
