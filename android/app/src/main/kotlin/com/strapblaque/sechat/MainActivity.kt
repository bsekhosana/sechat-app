package com.strapblaque.sechat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.strapblaque.sechat.SessionApi
import com.strapblaque.sechat.SessionApiImpl

class MainActivity : FlutterActivity() {
    private lateinit var sessionApiImpl: SessionApiImpl

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Session Protocol implementation
        sessionApiImpl = SessionApiImpl(this)
        
        // Set up Pigeon-generated SessionApi
        SessionApi.SessionApi.setUp(flutterEngine.dartExecutor.binaryMessenger, sessionApiImpl)
    }
} 