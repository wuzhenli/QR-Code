//
//  ViewController.m
//  二维码
//
//  Created by 李东喜 on 15/12/9.
//  Copyright © 2015年 don. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Masonry.h>

@interface ViewController ()  < 
    UITabBarDelegate,
    AVCaptureMetadataOutputObjectsDelegate,
    UINavigationControllerDelegate, 
    UIImagePickerControllerDelegate
>
@property (assign, nonatomic) CGRect originInterestRect;


@property (weak, nonatomic) IBOutlet UITabBar *customBar;

@property (strong, nonatomic) NSLayoutConstraint *containerHeightConstraint;
@property (strong, nonatomic) NSLayoutConstraint *scanLineTopConstraint;
@property (strong, nonatomic) UILabel *customLabel;

@property (strong, nonatomic) UIView *customContainerView;
@property (strong, nonatomic) UIImageView *imgViewBorder;
@property (strong, nonatomic) UIImageView *imgViewScannLine;

@property ( strong , nonatomic ) AVCaptureDevice * device;
@property ( strong , nonatomic ) AVCaptureDeviceInput * input;
@property ( strong , nonatomic ) AVCaptureMetadataOutput * output;
@property ( strong , nonatomic ) AVCaptureSession * session;
@property ( strong , nonatomic ) AVCaptureVideoPreviewLayer * previewLayer;
/*** 专门用于保存描边的图层 ***/
@property (nonatomic,strong) CALayer *containerLayer;


@end


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.customBar.selectedItem = self.customBar.items.firstObject;
    self.customBar.delegate = self;
    
    [self setup];
    [self setupUI];
    [self checkCameraAuthorizationCompletion:^(BOOL granted) {
        if (granted) {
            // 3.开始扫描二维码
            [self initScan];
            // 8.开始扫描
            [self.session startRunning];
        } else {
            // tip
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showNoCameraAuthorizationTip];
            });
        }
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 界面显示,开始动画
- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    
    if (_session && _session.isRunning == NO) {
        [_session startRunning];
    }
    [self startAnimation];
}

//注意，在界面消失的时候关闭session
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    if (_session && _session.isRunning) {
        [_session stopRunning];
    }
    [self removeAnimation];
    [self clearLayers];
}

- (void)setup {
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(appWillEnterForegroundNotification:) 
                                                 name:UIApplicationWillEnterForegroundNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(appDidEnterBackgroundNotification:) 
                                                 name:UIApplicationDidEnterBackgroundNotification 
                                               object:nil];
}
- (void)setupUI {
    CGFloat h = 300;
    CGFloat y = ([UIScreen mainScreen].bounds.size.height - h ) * 0.5;
    CGFloat x = ([UIScreen mainScreen].bounds.size.width - h ) * 0.5;
    self.originInterestRect = CGRectMake(x, y, h, h);
    
    [self.customContainerView addSubview:self.imgViewBorder];
    [self.imgViewBorder mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.customContainerView);
    }];
    
//    __block MASConstraint *consH = nil;
    __block MASConstraint *consTop = nil;
    [self.customContainerView addSubview:self.imgViewScannLine];
    [self.imgViewScannLine mas_makeConstraints:^(MASConstraintMaker *make) {
        consTop = make.top.equalTo(self.customContainerView);
        make.left.right.equalTo(self.customContainerView);
        make.height.equalTo(self.customContainerView);
    }];
    self.scanLineTopConstraint = [consTop valueForKey:@"layoutConstraint"];
    
    [self.view addSubview:self.customLabel];
    [self.customLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.customContainerView.mas_bottom).offset(20);
        make.left.right.equalTo(self.customContainerView);
    }];
}

/*---------------------------- 分割线 ---------------------------- */
- (void)initScan {
    // 1.判断输入能否添加到会话中
    if (![self.session canAddInput:self.input]) {
        NSLog(@"canAddInput error");
        return;  
    } 
    [self.session addInput:self.input];
    
    // 2.判断输出能够添加到会话中
    if (![self.session canAddOutput:self.output]) return;
    [self.session addOutput:self.output];
    
    // 4.设置输出能够解析的数据类型
    // 注意点: 设置数据类型一定要在输出对象添加到会话之后才能设置
    self.output.metadataObjectTypes = self.output.availableMetadataObjectTypes;
    
    // 5.设置监听监听输出解析到的数据
    [self.output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    
    // 6.添加预览图层
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];
    CGRect frame = self.view.bounds;
    frame = [UIScreen mainScreen].bounds;
    self.previewLayer.frame = frame;
    // self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    // 7.添加容器图层
    [self.view.layer addSublayer:self.containerLayer];
    self.containerLayer.frame = frame;
}

#pragma -mark event response

- (IBAction)closeButtonClick:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)openCameralClick:(id)sender {
    // 1.判断相册是否可以打开
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    // 2. 创建图片选择控制器
    UIImagePickerController *ipc = [[UIImagePickerController alloc] init];
    ipc.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    // 4.设置代理
    ipc.delegate = self;
    // 5.modal出这个控制器
    [self presentViewController:ipc animated:YES completion:nil];
}

- (void)appDidEnterBackgroundNotification:(NSNotification *)notification {
    if (_session) {
        [_session stopRunning];
        [self removeAnimation];
        [self clearLayers];
    }
}

- (void)appWillEnterForegroundNotification:(NSNotification *)notification {
    if (_session) {
        [_session startRunning];
        [self removeAnimation];
        [self startAnimation];
    }
}


#pragma mark -------- UIImagePickerControllerDelegate---------
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{
    // 1.取出选中的图片
    UIImage *pickImage = info[UIImagePickerControllerOriginalImage];
    NSData *imageData = UIImagePNGRepresentation(pickImage);

    CIImage *ciImage = [CIImage imageWithData:imageData];
    
    // 2.从选中的图片中读取二维码数据
    // 2.1创建一个探测器
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyLow}];
    
    // 2.2利用探测器探测数据
    NSArray *feature = [detector featuresInImage:ciImage];

    // 2.3取出探测到的数据
    for (CIQRCodeFeature *result in feature) {
        NSString *urlStr = result.messageString;
        if (urlStr) {
            NSLog(@"%@",result.messageString);
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]];
            break;
        }
    }
    
    // 注意: 如果实现了该方法, 当选中一张图片时系统就不会自动关闭相册控制器
    [picker dismissViewControllerAnimated:YES completion:nil];
}




#pragma mark --------AVCaptureMetadataOutputObjectsDelegate ---------

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
  //  if (metadataObjects.count > 0) {
        // id 类型不能点语法,所以要先去取出数组中对象
    AVMetadataMachineReadableCodeObject *object = [metadataObjects lastObject];
    if (object == nil) return;
    if ([object isKindOfClass:[AVMetadataFaceObject class]]) {
        NSLog(@"扫描非字符串 ：%@",object);
        return;
    }
    // 只要扫描到结果就会调用
    self.customLabel.text = object.stringValue;
    [self clearLayers];
    
   // [self.previewLayer removeFromSuperlayer];
    // 2.对扫描到的二维码进行描边
    AVMetadataMachineReadableCodeObject *obj = (AVMetadataMachineReadableCodeObject *)[self.previewLayer transformedMetadataObjectForMetadataObject:object];
    [self drawLine:obj];
    // 停止扫描
    [self.session stopRunning];
    [self removeAnimation];
//        // 将预览图层移除
//        [self.previewLayer removeFromSuperlayer];
//    } else {
//        NSLog(@"没有扫描到数据");
//    }
}

// 绘制描边
- (void)drawLine:(AVMetadataMachineReadableCodeObject *)objc {
    NSArray *array = objc.corners;
    // 1.创建形状图层, 用于保存绘制的矩形
    CAShapeLayer *layer = [[CAShapeLayer alloc] init];

    // 设置线宽
    layer.lineWidth = 2;
    layer.strokeColor = [UIColor greenColor].CGColor;
    layer.fillColor = [UIColor clearColor].CGColor;

    // 2.创建UIBezierPath, 绘制矩形
    UIBezierPath *path = [[UIBezierPath alloc] init];
    CGPoint point = CGPointZero;
    int index = 0;
    
    CFDictionaryRef dict = (__bridge CFDictionaryRef)(array[index++]);
    // 把点转换为不可变字典
    // 把字典转换为点，存在point里，成功返回true 其他false
    CGPointMakeWithDictionaryRepresentation(dict, &point);
    
    [path moveToPoint:point];
    
    // 2.2连接其它线段
    for (int i = 1; i<array.count; i++) {
        CGPointMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)array[i], &point);
        [path addLineToPoint:point];
    }
    // 2.3关闭路径
    [path closePath];
    
    layer.path = path.CGPath;
    // 3.将用于保存矩形的图层添加到界面上
    [self.containerLayer addSublayer:layer];
    
}

- (void)clearLayers {
    if (self.containerLayer.sublayers) {
        for (CALayer *subLayer in self.containerLayer.sublayers)
            [subLayer removeFromSuperlayer];
    }
}


// 开启冲击波动画
- (void)startAnimation {
    // 1.设置冲击波底部和容器视图顶部对齐
    self.scanLineTopConstraint.constant = - self.containerHeightConstraint.constant;
    // 刷新UI
    [self.view layoutIfNeeded];
    // 2.执行扫描动画
    [UIView animateWithDuration:1.0 animations:^{
        // 无线重复动画
        [UIView setAnimationRepeatCount:MAXFLOAT];
        self.scanLineTopConstraint.constant = self.containerHeightConstraint.constant;
        // 刷新UI
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)removeAnimation {
    // 移除动画
    [self.imgViewScannLine.layer removeAllAnimations];
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
    // 根据当前选中的按钮重新设置二维码容器高度
    self.containerHeightConstraint.constant = item.tag == 1 ? 150 : 300;
    // 刷新UI
    [self.view layoutIfNeeded];
    
    [self removeAnimation];
    [self startAnimation];
}

- (void)showNoCameraAuthorizationTip {
    NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *info = [bundle infoDictionary];
    NSString *prodName = [info objectForKey:@"CFBundleDisplayName"];
    
    NSString *tipText = [NSString stringWithFormat:@"请在 iPhone 的\"设置-隐私-相机\"选项中，允许\"%@\"访问你的相机", prodName];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:tipText preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        ;
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma -mark private

- (void)checkCameraAuthorizationCompletion:(void(^)(BOOL granted))completion {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    switch (status) {
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    !completion ? : completion(granted);
                });
            }];
            break;
        }
        case AVAuthorizationStatusRestricted:
        case AVAuthorizationStatusDenied:
            completion(NO);
            break;
        case AVAuthorizationStatusAuthorized:
            completion(YES);
            break;
    }
}

#pragma mark -------- 懒加载---------
- (AVCaptureDevice *)device {
    if (_device == nil) {
        _device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    return _device;
}

- (AVCaptureDeviceInput *)input {
    if (_input == nil) {
        _input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:nil];
    }
    return _input;
}

- (AVCaptureSession *)session {
    if (_session == nil) {
        _session = [[AVCaptureSession alloc] init];
    }
    return _session;
}

- (AVCaptureVideoPreviewLayer *)previewLayer {
    if (_previewLayer == nil) {
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    }
    return _previewLayer;
}

// 设置输出对象解析数据时感兴趣的范围
// 默认值是 CGRect(x: 0, y: 0, width: 1, height: 1)
// 通过对这个值的观察, 我们发现传入的是比例
// 注意: 参照是以横屏的左上角作为, 而不是以竖屏
//        out.rectOfInterest = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
- (AVCaptureMetadataOutput *)output
{
    if (_output == nil) {
        _output = [[AVCaptureMetadataOutput alloc] init];
        
        // 1.获取屏幕的frame
        CGRect viewRect = self.view.frame;
        // 2.获取扫描容器的frame
        CGRect containerRect = self.originInterestRect;
        
        CGFloat x = containerRect.origin.y / viewRect.size.height;
        CGFloat y = containerRect.origin.x / viewRect.size.width;
        CGFloat width = containerRect.size.height / viewRect.size.height;
        CGFloat height = containerRect.size.width / viewRect.size.width;
        
        // CGRect outRect = CGRectMake(x, y, width, height);
        // [_output rectForMetadataOutputRectOfInterest:outRect];
        _output.rectOfInterest = CGRectMake(x, y, width, height);
    }
    return _output;
}

- (CALayer *)containerLayer {
    if (_containerLayer == nil) {
        _containerLayer = [[CALayer alloc] init];
    }
    return _containerLayer;
}

- (UIView *)customContainerView {
    if (!_customContainerView) {
        _customContainerView = [UIView new];
        [self.view addSubview:_customContainerView];
        __block MASConstraint *consH = nil;
        [_customContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
            consH = make.height.mas_equalTo(self.originInterestRect.size.height);
            make.width.mas_equalTo(self.originInterestRect.size.width);
            make.left.offset(self.originInterestRect.origin.x);
            make.top.offset(self.originInterestRect.origin.y);
        }];
        self.containerHeightConstraint = [consH valueForKey:@"layoutConstraint"];
        _customContainerView.layer.masksToBounds = YES;
    }
    return _customContainerView;
}

- (UIImageView *)imgViewBorder {
    if (!_imgViewBorder) {
        _imgViewBorder = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"qrcode_border"]];
    }
    return _imgViewBorder;
}

- (UIImageView *)imgViewScannLine {
    if (!_imgViewScannLine) {
        _imgViewScannLine  = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"qrcode_scanline_qrcode"]];
    }
    return _imgViewScannLine;
}

- (UILabel *)customLabel {
    if (!_customLabel) {
        _customLabel = [[UILabel alloc] init];
        _customLabel.textColor = [UIColor blackColor];
        _customLabel.textAlignment = NSTextAlignmentCenter;
        _customLabel.font = [UIFont systemFontOfSize:17];
    }
    return _customLabel;
}


@end
