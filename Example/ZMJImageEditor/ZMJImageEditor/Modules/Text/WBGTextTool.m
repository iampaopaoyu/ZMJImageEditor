//
//  WBGTextTool.m
//  CLImageEditorDemo
//
//  Created by Jason on 2017/3/1.
//  Copyright © 2017年 CALACULU. All rights reserved.
//

#import "WBGTextTool.h"
#import "WBGTextToolView.h"
#import "FrameAccessor.h"
#import "WBGTextColorPanel.h"
#import "WBGChatMacros.h"
#import "WBGNavigationBarView.h"
#import "EXTobjc.h"
#import "WBGDrawView.h"
#import "WBGTextToolOverlapView.h"

static const CGFloat kTopOffset = 50.f;
static const CGFloat kTextTopOffset = 60.f;
static const NSInteger kTextMaxLimitNumber = 100;

@interface WBGTextTool ()
@property (nonatomic, weak) WBGDrawView *drawingView;
@property (nonatomic, weak) WBGTextColorPanel *textColorPanel;
@end

@implementation WBGTextTool

- (void)setup
{
    _drawingView = self.editor.drawingView;
    self.editor.scrollView.pinchGestureRecognizer.enabled = NO;
    
    self.textView = [[WBGTextView alloc] initWithFrame:CGRectMake(0, 0, WIDTH_SCREEN, HEIGHT_SCREEN)];
    self.textView.textView.font = [UIFont systemFontOfSize:25.f weight:UIFontWeightBold];
    self.textView.textView.textColor = [UIColor whiteColor];
    self.textColorPanel = self.textView.colorPanel;
    
    [self setupActions];
    
    [self.editor.view addSubview:self.textView];
}

- (void)setupActions
{
    @weakify(self);
    
    self.textView.dissmissTextTool = ^(NSString *currentText, BOOL isUse)
    {
        @strongify(self);
        
        self.editor.scrollView.pinchGestureRecognizer.enabled = YES;
        
        if (self.isEditAgain)
        {
            if (self.editAgainCallback && isUse)
            {
                self.editAgainCallback(currentText);
            }
            
            self.isEditAgain = NO;
        }
        else
        {
            if (isUse)
            {
                [self addNewText:currentText];
            }
        }
        
        if (self.dissmissTextTool)
        {
            self.dissmissTextTool(currentText);
        }
    };
    
    self.textColorPanel.onTextColorChange = ^(UIColor *color) {
        @strongify(self);
        [self changeColor:color];
    };
}

- (void)cleanup
{
    [self.textView removeFromSuperview];
}

- (void)hideTools:(BOOL)hidden
{
    if (hidden)
    {
        self.editor.bottomBar.alpha = 0;
    }
    else
    {
        self.editor.bottomBar.alpha = 1.0f;
    }
}

- (void)hideTextBorder
{
    for (UIView *v in self.editor.drawingView.subviews)
    {
        if ([v isKindOfClass:[WBGTextToolView class]])
        {
            [v setHidden:YES];
        }
    }
}

- (void)changeColor:(UIColor *)color
{
    if (color && self.textView)
    {
        [self.textView.textView setTextColor:color];
    }
}

- (void)addNewText:(NSString *)text
{
    if (text == nil || text.length <= 0)
    {
        return;
    }
    
    WBGTextToolView *view = [[WBGTextToolView alloc] initWithTool:self text:text font:self.textView.textView.font orImage:nil];
    view.fillColor = self.textColorPanel.currentColor;
    view.borderColor = [UIColor whiteColor];
    view.font = self.textView.textView.font;
    view.text = text;
    view.center = [self.editor.imageView.superview convertPoint:self.editor.imageView.center toView:self.editor.drawingView];
    view.userInteractionEnabled = YES;
    
    [self.editor.drawingView addSubview:view];
    
    // 更新位置 不然旋转了
    CGFloat scale = [(NSNumber *)[self.editor.drawingView valueForKeyPath:@"layer.transform.rotation"] floatValue];
    [view rotate:-scale];
    
    [WBGTextToolView setActiveTextView:view];
}

@end



#pragma mark - WBGTextView
@interface WBGTextView () <YYTextViewDelegate>
@property (nonatomic, strong) NSString *needReplaceString;
@property (nonatomic, assign) NSRange   needReplaceRange;
@property (nonatomic, strong) WBGNavigationBarView *navigationBarView;
@end

@implementation WBGTextView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self)
    {
        self.backgroundColor = [UIColor clearColor];
        
        self.effectView = [[UIView alloc] init];
        self.effectView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7f];
        self.effectView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
        [self addSubview:self.effectView];
        
        self.navigationBarView = [WBGNavigationBarView xx_instantiateFromNib];
        self.navigationBarView.frame = CGRectMake(0, 0, WIDTH_SCREEN, [WBGNavigationBarView fixedHeight]);
        [self addSubview:self.navigationBarView];
        
        
        self.textView = [[YYTextView alloc] initWithFrame:CGRectMake(16, kTopOffset, WIDTH_SCREEN - 16 * 2, HEIGHT_SCREEN - kTopOffset)];
        self.textView.top = kTextTopOffset;
        self.textView.scrollEnabled = YES;
        self.textView.returnKeyType = UIReturnKeyDone;
        self.textView.delegate = self;
        self.textView.backgroundColor = [UIColor clearColor];
        [self addSubview:self.textView];
        
        WBGTextColorPanel *colorPanel = [WBGTextColorPanel xx_instantiateFromNib];
        colorPanel.frame = CGRectMake(0, HEIGHT_SCREEN, WIDTH_SCREEN, [WBGTextColorPanel fixedHeight]);
        [self addSubview:colorPanel];
        self.colorPanel = colorPanel;
        
        [self setupActions];
        [self addNotify];
    }
    
    return self;
}

- (void)setupActions
{
    __weak __typeof(self)weakSelf = self;
   
    self.navigationBarView.onDoneButtonClickBlock = ^(UIButton *btn) {
        [weakSelf dismissTextEditing:YES];
    };
    
    self.navigationBarView.onCancelButtonClickBlock = ^(UIButton *btn) {
        [weakSelf dismissTextEditing:NO];
    };
}

- (void)addNotify
{
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(keyboardWillShow:)
     name:UIKeyboardWillShowNotification
     object:nil];
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(keyboardWillHide:)
     name:UIKeyboardWillHideNotification
     object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    NSDictionary *userinfo = notification.userInfo;
    CGRect  keyboardRect              = [[userinfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardAnimationDuration = [[userinfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions keyboardAnimationCurve = [[userinfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    
    
    self.hidden = YES;
    [UIView
     animateWithDuration:keyboardAnimationDuration
     delay:keyboardAnimationDuration
     options:keyboardAnimationCurve
     animations:^{
        self.textView.height = HEIGHT_SCREEN - keyboardRect.size.height - kTextTopOffset;
        
        self.colorPanel.frame = CGRectMake(0, HEIGHT_SCREEN - [WBGTextColorPanel fixedHeight] - keyboardRect.size.height, WIDTH_SCREEN, [WBGTextColorPanel fixedHeight]);
        
    } completion:NULL];
    
    [UIView animateWithDuration:3 animations:^{
        self.hidden = NO;
    }];
    
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    NSDictionary *userinfo = notification.userInfo;
    CGFloat keyboardAnimationDuration = [[userinfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions keyboardAnimationCurve = [[userinfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue];
    
    
    [UIView animateWithDuration:keyboardAnimationDuration delay:0.f options:keyboardAnimationCurve animations:^{
        self.top = self.effectView.height + kTopOffset;
    } completion:^(BOOL finished) {
        
    }];
}

- (void)dismissTextEditing:(BOOL)done
{
    [self.textView resignFirstResponder];
    
    if (self.dissmissTextTool)
    {
        self.dissmissTextTool(self.textView.text, done);
    }
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    if (newSuperview)
    {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.textView becomeFirstResponder];
            [self.textView scrollRangeToVisible:NSMakeRange(self.textView.text.length-1, 0)];
        });
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    // 选中范围的标记
    UITextRange *textSelectedRange = [textView markedTextRange];
    // 获取高亮部分
    UITextPosition *textPosition = [textView positionFromPosition:textSelectedRange.start offset:0];
    // 如果在变化中是高亮部分在变, 就不要计算字符了
    if (textSelectedRange && textPosition) {
        return;
    }
    // 文本内容
    NSString *textContentStr = textView.text;
    NSLog(@"text = %@",textView.text);
    NSInteger existTextNumber = textContentStr.length;
    
    if (existTextNumber > kTextMaxLimitNumber) {
        // 截取到最大位置的字符(由于超出截取部分在should时被处理了,所以在这里为了提高效率不在判断)
        NSString *str = [textContentStr substringToIndex:kTextMaxLimitNumber];
        [textView setText:str];
        //[AlertBox showMessage:@"输入字符不能超过100\n多余部分已截断" hideAfter:3];
    }
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    NSLog(@"%@", text);
    if ([text isEqualToString:@"\n"])
    {
        [self dismissTextEditing:YES];
        return NO;
    }
    
    UITextRange *selectedRange = [textView markedTextRange];
    //获取高亮部分
    UITextPosition *pos = [textView positionFromPosition:selectedRange.start offset:0];
    
    //如果有高亮且当前字数开始位置小于最大限制时允许输入
    if (selectedRange && pos) {
        NSInteger startOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:selectedRange.start];
        NSInteger endOffset = [textView offsetFromPosition:textView.beginningOfDocument toPosition:selectedRange.end];
        NSRange offsetRange = NSMakeRange(startOffset, endOffset - startOffset);
        
        if (offsetRange.location < kTextMaxLimitNumber && textView.text.length - offsetRange.length <= kTextMaxLimitNumber) {
            self.needReplaceRange = offsetRange;
            self.needReplaceString = text;
            return YES;
        }
        else
        {
            return NO;
        }
    }
    
    
    NSString *comcatstr = [textView.text stringByReplacingCharactersInRange:range withString:text];
    
    NSInteger caninputlen = kTextMaxLimitNumber - comcatstr.length;
    
    if (caninputlen >= 0)
    {
        return YES;
    }
    else
    {
        NSInteger len = text.length + caninputlen;
        //防止当text.length + caninputlen < 0时，使得rg.length为一个非法最大正数出错
        NSRange rg = {0,MAX(len,0)};
        
        if (rg.length > 0)
        {
            NSString *s = @"";
            //判断是否只普通的字符或asc码(对于中文和表情返回NO)
            BOOL asc = [text canBeConvertedToEncoding:NSASCIIStringEncoding];
            if (asc) {
                s = [text substringWithRange:rg];//因为是ascii码直接取就可以了不会错
            }
            else
            {
                __block NSInteger idx = 0;
                __block NSString  *trimString = @"";//截取出的字串
                //使用字符串遍历，这个方法能准确知道每个emoji是占一个unicode还是两个
                [text enumerateSubstringsInRange:NSMakeRange(0, [text length])
                                         options:NSStringEnumerationByComposedCharacterSequences
                                      usingBlock: ^(NSString* substring, NSRange substringRange, NSRange enclosingRange, BOOL* stop) {
                                          
                                          NSInteger steplen = substring.length;
                                          if (idx >= rg.length) {
                                              *stop = YES; //取出所需要就break，提高效率
                                              return ;
                                          }
                                          
                                          trimString = [trimString stringByAppendingString:substring];
                                          
                                          idx = idx + steplen;//这里变化了，使用了字串占的长度来作为步长
                                      }];
                
                s = trimString;
            }
            //rang是指从当前光标处进行替换处理(注意如果执行此句后面返回的是YES会触发didchange事件)
            [textView setText:[textView.text stringByReplacingCharactersInRange:range withString:s]];
        }
        return NO;
    }
}

@end
