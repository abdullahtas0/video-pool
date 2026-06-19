Pod::Spec.new do |s|
  s.name             = 'video_pool'
  s.version          = '0.1.0'
  s.summary          = 'Video pool native monitoring for iOS'
  s.description      = <<-DESC
  Native iOS layer for video_pool Flutter plugin. Provides thermal monitoring,
  memory pressure detection, hardware capability querying, and audio focus management.
                       DESC
  s.homepage         = 'https://github.com/abdullahtas0/video-pool'
  s.license          = { :type => 'MIT' }
  s.author           = { 'video_pool' => 'dev.abdullahtas@gmail.com' }
  s.source           = { :http => 'https://github.com/abdullahtas0/video-pool' }
  # Sources are shared with Swift Package Manager (see video_pool/Package.swift).
  # Both build systems compile the same files under video_pool/Sources/video_pool.
  s.source_files     = 'video_pool/Sources/video_pool/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
