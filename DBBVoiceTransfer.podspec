#
#  Be sure to run `pod spec lint DBBVoiceTransfer.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|
  s.name         = "DBBVoiceTransfer"
  s.version      = "0.0.6"
  s.summary      = "声音转换的SDK"
  s.description  = <<-DESC
标贝科技- iOS 变声SDK
                   DESC
  s.homepage     = "https://github.com/data-baker/BakerVoiceConvertIOS"
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author             = { "linxi" => "linxi@data-baker.com" }
  s.ios.deployment_target = '9.0'
  s.source       = { :git => 'https://github.com/data-baker/BakerVoiceConvertIOS.git', :tag => s.version}
   s.source_files  = 'DBVoiceTransfer/DBVoiceTransfer/DBBVoiceTransfer/*.{h,m}'
   s.dependency 'DBCommonLib'

end
