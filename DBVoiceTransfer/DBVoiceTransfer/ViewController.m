//
//  ViewController.m
//  DBVoiceTransfer
//
//  Created by linxi on 2021/3/18.
//

#import "ViewController.h"
#import "DBVoiceTransferUtil.h"
#import "DBLoginVC.h"
#import "XCHudHelper.h"
#import "UIView+Toast.h"

static NSString *DBAudioMicroData = @"audioMicroData";



@interface ViewController ()<UIPickerViewDelegate,UIPickerViewDataSource,DBTransferProtocol>
@property (weak, nonatomic) IBOutlet UILabel *desLabel;
@property (weak, nonatomic) IBOutlet UILabel *msgLabel;
@property (weak, nonatomic) IBOutlet UITextField *modelTextField;
@property (weak, nonatomic) IBOutlet UIButton *startButton;
@property (weak, nonatomic) IBOutlet UIButton *fileButton;
@property (weak, nonatomic) IBOutlet UIImageView *voiceImageView;

@property(nonatomic,strong)NSArray * pickerArray;

@property (nonatomic, strong)DBVoiceTransferUtil * voiceTransferUtil;

/// 麦克风采集的数据
@property(nonatomic,strong)NSMutableData * micAudioData;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.pickerArray = @[@"Vc_jiaojiao",@"Vc_tiantian",@"far-field",@"Vc_baklong",@"Vc_ledi",@"Vc_weimian"];
    self.micAudioData = [NSMutableData data];
    [self setupSubView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *clientId = [[NSUserDefaults standardUserDefaults] objectForKey:clientIdKey];
    NSString *clientSecret = [[NSUserDefaults standardUserDefaults] objectForKey:clientSecretKey];
    if (!clientSecret || !clientId) {
        [self showLogInVC];
        return ;
    }
    
    [[XCHudHelper sharedInstance] showHudOnView:self.view caption:@"" image:nil acitivity:YES autoHideTime:0];
    [[DBVoiceTransferUtil shareInstance] setupClientId:clientId clientSecret:clientSecret block:^(NSString * _Nullable token, NSError * _Nullable error) {
            if (error) {
                [[XCHudHelper sharedInstance] hideHud];
                NSLog(@"获取token失败:%@",error);
                NSString *msg = [NSString stringWithFormat:@"获取token失败:%@",error.description];
                [self.view makeToast:msg duration:2 position:CSToastPositionCenter];
                return;
            }
            [[XCHudHelper sharedInstance] hideHud];
            [[NSUserDefaults standardUserDefaults]setObject:clientId forKey:clientIdKey];
            [[NSUserDefaults standardUserDefaults]setObject:clientSecret forKey:clientSecretKey];
            [[NSUserDefaults standardUserDefaults]setObject:token forKey:@"token"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self dismissViewControllerAnimated:YES completion:nil];

        }];
    
}

- (void)showLogInVC {
    UIStoryboard *story = [UIStoryboard storyboardWithName:@"Main" bundle:[NSBundle mainBundle]];
        DBLoginVC *loginVC  =   [story instantiateViewControllerWithIdentifier:@"DBLoginVC"];
    loginVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:loginVC animated:YES completion:nil];
}

- (void)setupSubView {
    _desLabel.text = @"使用说明：\n 1.选择音色；\n 2.点击开始录音转换，录音结束后点击停止录音转换； \n 3.声音转换完全直接进行播放；\n 4.本地文件转换会直接读取本地音频文件进行声音转换。";
    [self creatPickerView];
    self.modelTextField.text = self.pickerArray.firstObject;
}

-(void)creatPickerView  {
    CGFloat width = self.view.frame.size.width;
    
    UIPickerView  * pickerView = [[UIPickerView alloc]initWithFrame:CGRectMake(0, 0, width, 150)];
    pickerView.delegate = self;
    pickerView.dataSource = self;
    pickerView.backgroundColor = [UIColor whiteColor];
    UIToolbar  *toolBar = [[UIToolbar alloc]initWithFrame:CGRectMake(0, 0, width, 44)];
    
    //设置toolBar的样式
    //toolbar.barStyle = UIBarStyleDefault;
    
    /***必要步骤****/
    self.modelTextField.inputView = pickerView;
    self.modelTextField.inputAccessoryView = toolBar;
    
    //这个是toolBar上的确定按钮
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneTouched:)];
    doneButton.title = @"确定";
    //取消按钮
    UIBarButtonItem *cancleButton = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancleTouched:)];
    cancleButton.title = @"取消";
    //将取消按钮，一个空白的填充item和一个确定按钮放入toolBar
    [toolBar setItems:[NSArray arrayWithObjects:cancleButton,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],doneButton, nil]];
}

- (IBAction)recordVoiceButton:(id)sender {
    UIButton *button = sender;
    button.selected = !button.isSelected;
    [self startRecord:button.isSelected];
    
}
- (void)startRecord:(BOOL)isStart {
    if (isStart) {
        [self.micAudioData resetBytesInRange:NSMakeRange(0, self.micAudioData.length)];
        [self.voiceTransferUtil startTransferNeedPlay:YES];
        self.voiceImageView.hidden = NO;
    }else {
        self.voiceImageView.hidden = YES;
        [self.voiceTransferUtil endRecognizeAndCloseSocket];
    }
}


- (IBAction)localFileVoiceTransfer:(id)sender {
    UIButton *button = sender;
    button.selected = !button.isSelected;
    if (button.isSelected) {
        [[XCHudHelper sharedInstance] showHudOnView:self.view caption:@"文件转换中..." image:nil acitivity:YES autoHideTime:0];

        [self.voiceTransferUtil startTransferWithFilePath:[self.voiceTransferUtil getSavePath:DBAudioMicroData] needPaley:YES];
    }else {
        [self.voiceTransferUtil endFileTransferAndCloseSocket];
    }
    
}


#pragma mark -toolBarBarItem的方法
-(void)doneTouched:(UIBarButtonItem *)sender{
//将textField的第一响应取消
    [self.modelTextField resignFirstResponder];
}
-(void)cancleTouched:(UIBarButtonItem *)sender{
 
//将textField的第一响应取消
    [self.modelTextField resignFirstResponder];
}

#pragma mark - pickerViewDelegate&dataSource
//返回picker有几列
-(NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView{
    return 1;
}
//返回每列有几行
-(NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component{
//数据源
    return [self.pickerArray count];
}
//返回每行显示的内容
-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component{
    NSString *item = [self.pickerArray objectAtIndex:row];

    return item;
}

- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view{
    UILabel* pickerLabel = (UILabel*)view;
    if (!pickerLabel){
        pickerLabel = [[UILabel alloc] init];
        pickerLabel.adjustsFontSizeToFitWidth = YES;
        [pickerLabel setTextAlignment:NSTextAlignmentCenter];
        [pickerLabel setBackgroundColor:[UIColor systemTealColor]];
        [pickerLabel setFont:[UIFont boldSystemFontOfSize:16]];
    }
    // Fill the label text here
    pickerLabel.text=[self pickerView:pickerView titleForRow:row forComponent:component];
    return pickerLabel;
}
//picker选取某一行执行的方法
-(void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component{
    self.modelTextField.text =  self.pickerArray[row];
    self.voiceTransferUtil.voiceName = self.pickerArray[row];
}

- (void)onError:(NSInteger)code message:(NSString *)message {
    if (code == DBErrorStateFileReadFailed) {
        [[XCHudHelper sharedInstance] hideHud];
        [self.view makeToast:message duration:2 position:CSToastPositionCenter];
        return;
    }
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults removeObjectForKey:@"token"];
    [userDefaults removeObjectForKey:clientSecretKey];
    [userDefaults removeObjectForKey:clientIdKey];
    [self showLogInVC];
    self.voiceImageView.hidden = YES;
}

- (void)microphoneAudioData:(NSData *)data isLast:(BOOL)isLast {
    [self.micAudioData appendData:data];
    if (isLast) {
        [self.micAudioData writeToFile:[self.voiceTransferUtil getSavePath:DBAudioMicroData] atomically:YES];
        NSLog(@"self.micAudioData length:%@",@(self.micAudioData.length));
    }
}



- (void)dbValues:(NSInteger)db {
    NSUInteger volumeDB = db;
    static NSInteger index = 0;
    index++;
    if (index == 1) {
        index = 0;
    }else {
        return;
    }
    if (volumeDB < 30) {
        self.voiceImageView.image = [UIImage imageNamed:@"1"];
    }else if (volumeDB < 40) {
        self.voiceImageView.image = [UIImage imageNamed:@"2"];
    }else if (volumeDB < 50) {
        self.voiceImageView.image = [UIImage imageNamed:@"3"];
    }else if (volumeDB < 55) {
        self.voiceImageView.image = [UIImage imageNamed:@"4"];
    }else if (volumeDB < 60) {
        self.voiceImageView.image = [UIImage imageNamed:@"5"];
    }else if (volumeDB < 70) {
        self.voiceImageView.image = [UIImage imageNamed:@"6"];
    }else if (volumeDB < 80) {
        self.voiceImageView.image = [UIImage imageNamed:@"7"];
    }else{
        self.voiceImageView.image = [UIImage imageNamed:@"8"];
    }
}

- (void)transferCallBack:(NSData *)data isLast:(BOOL)isLast {
    NSLog(@"dataLength:%@ isLast:%@,",@(data.length),@(isLast));
    
    if (isLast) {
        self.fileButton.selected = NO;
        [[XCHudHelper sharedInstance] hideHud];
    }
    
}

- (void)readlyToPlay {
    NSLog(@"%s readlyToPlay",__func__);
}
- (void)playFinished {
    NSLog(@"%s playFinished",__func__);
}


// MARK: -- Setter&Getter Methods

- (DBVoiceTransferUtil *)voiceTransferUtil {
    if (!_voiceTransferUtil) {
        _voiceTransferUtil = [DBVoiceTransferUtil shareInstance];
        _voiceTransferUtil.log = YES;
        _voiceTransferUtil.voiceName = self.pickerArray.firstObject;
        _voiceTransferUtil.delegate = self;        
    }
    return _voiceTransferUtil;
}

@end
