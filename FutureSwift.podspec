#
# Be sure to run `pod lib lint Future.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "FutureSwift"
  s.module_name      = "Future"
  s.version          = "1.1.8"
  s.summary          = "Light, Sexy and type safe Future & Promise implementation in Swift."
  s.homepage         = "https://github.com/othierry/future"
  s.license          = 'MIT'
  s.author           = { "Olivier Thierry" => "olivier.thierry42@gmail.com" }
  s.source           = { :git => "https://github.com/othierry/future.git", :tag => s.version.to_s }

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'
end
