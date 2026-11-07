package de.alhayali.moneva;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class MainActivity extends FlutterActivity {
    private InvoiceImageEncoder invoiceImageEncoder;

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        invoiceImageEncoder = new InvoiceImageEncoder(
                flutterEngine.getDartExecutor().getBinaryMessenger());
    }

    @Override
    public void cleanUpFlutterEngine(FlutterEngine flutterEngine) {
        if (invoiceImageEncoder != null) {
            invoiceImageEncoder.close();
            invoiceImageEncoder = null;
        }
        super.cleanUpFlutterEngine(flutterEngine);
    }
}
