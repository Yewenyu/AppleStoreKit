
Pod::Spec.new do |s|
  s.name             = 'AppleStoreKit'
  s.version          = '0.1.7'
  s.summary          = 'A library that is compatible with StoreKit and StoreKit v2.'
  s.description      = <<-DESC
This library provides functionality to work with both StoreKit and StoreKit v2 in iOS applications.
                       DESC
  s.homepage         = 'https://github.com/Yewenyu/AppleStoreKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Ye' => '289193866@qq.com' }
  s.source           = { :git => 'https://github.com/Yewenyu/AppleStoreKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.swift_version = '5.0'

  s.source_files = 'AppleStoreKit'

  s.frameworks = 'StoreKit'
end
