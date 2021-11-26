//
//  ViewController.m
//  AudioDemo
//
//  Created by 罗海雄 on 2021/11/17.
//

#import "ViewController.h"
#import "AVAudioRecoder.h"
#import "VideoViewController.h"

@interface ViewController ()

@property(nonatomic, strong) AVAudioRecoder *recorder;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = UIColor.whiteColor;
    self.recorder = [AVAudioRecoder new];
    
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:@"开始" forState:UIControlStateNormal];
    [btn setTitle:@"停止" forState:UIControlStateSelected];
    [btn addTarget:self action:@selector(handleTap:) forControlEvents:UIControlEventTouchUpInside];
    btn.bounds = CGRectMake(0, 0, 100, 30);
    btn.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    [self.view addSubview:btn];
}

- (void)handleTap:(UIButton*) btn
{
    btn.selected = !btn.selected;
    if (btn.selected) {
        [self.recorder start];
    } else {
        [self.recorder stop];
    }
}

@end
