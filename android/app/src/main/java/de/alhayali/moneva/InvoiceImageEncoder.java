package de.alhayali.moneva;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.os.Handler;
import android.os.Looper;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/** Sample before decoding; never send full-size pixels through Flutter/PNG. */
final class InvoiceImageEncoder {
    private static final long MAX_BYTES = 25L * 1024 * 1024;
    private static final int SOFT_BYTES = 1024 * 1024;
    private static final double MAX_PIXELS = 4_000_000;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final MethodChannel channel;
    private volatile boolean closed;

    InvoiceImageEncoder(BinaryMessenger messenger) {
        channel = new MethodChannel(messenger, "paxfox/invoice_images");
        channel.setMethodCallHandler((call, result) -> {
            if (!call.method.equals("prepare")) {
                result.notImplemented();
                return;
            }
            final String path = call.argument("path");
            worker.execute(() -> {
                try {
                    byte[] bytes = prepare(new File(path == null ? "" : path));
                    main.post(() -> { if (!closed) result.success(bytes); });
                } catch (Exception | OutOfMemoryError error) {
                    main.post(() -> {
                        if (!closed) result.error("image_preparation",
                                "Cannot prepare this image. Choose a readable image under 25 MB.", null);
                    });
                }
            });
        });
    }

    void close() {
        closed = true;
        channel.setMethodCallHandler(null);
        // Let the current native decode release its bitmap, then retire its thread.
        worker.shutdown();
    }

    static byte[] prepare(File file) throws IOException {
        if (!file.isFile() || file.length() == 0 || file.length() > MAX_BYTES) {
            throw new IOException("Invalid image size");
        }
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getPath(), bounds);
        int width = bounds.outWidth;
        int height = bounds.outHeight;
        if (width <= 0 || height <= 0) throw new IOException("Invalid image header");
        int orientation;
        try {
            orientation = new ExifInterface(file.getPath()).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
        } catch (IOException unsupportedMetadata) {
            orientation = ExifInterface.ORIENTATION_NORMAL;
        }
        double scale = Math.min(1.0, Math.min(2000.0 / Math.min(width, height),
                Math.min(6000.0 / Math.max(width, height),
                        Math.sqrt(MAX_PIXELS / ((double) width * height)))));
        // Header checks avoid even decoding already suitable JPEGs.
        if (scale == 1.0 && (orientation == 0 || orientation == 1)
                && "image/jpeg".equals(bounds.outMimeType) && file.length() <= SOFT_BYTES) {
            try (FileInputStream input = new FileInputStream(file);
                 ByteArrayOutputStream output = new ByteArrayOutputStream((int) file.length())) {
                byte[] buffer = new byte[16384];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                return output.toByteArray();
            }
        }
        int targetWidth = Math.max(1, (int) Math.floor(width * scale));
        int targetHeight = Math.max(1, (int) Math.floor(height * scale));
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inPreferredConfig = Bitmap.Config.ARGB_8888;
        options.inSampleSize = 1;
        while (options.inSampleSize <= (1 << 28)
                && (width / options.inSampleSize > targetWidth
                    || height / options.inSampleSize > targetHeight)
                && Math.max(1, width / (options.inSampleSize * 2)) >= targetWidth
                && Math.max(1, height / (options.inSampleSize * 2)) >= targetHeight) {
            options.inSampleSize *= 2;
        }
        Bitmap bitmap = BitmapFactory.decodeFile(file.getPath(), options);
        if (bitmap == null) throw new IOException("Unreadable image");
        try {
            // A sampled decode uses at most ~16 MP; the final bitmap uses <=4 MP.
            Bitmap resized = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true);
            if (resized != bitmap) {
                bitmap.recycle();
                bitmap = resized;
            }
            Matrix transform = new Matrix();
            switch (orientation) {
                case ExifInterface.ORIENTATION_FLIP_HORIZONTAL: transform.setScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_180: transform.setRotate(180); break;
                case ExifInterface.ORIENTATION_FLIP_VERTICAL: transform.setScale(1, -1); break;
                case ExifInterface.ORIENTATION_TRANSPOSE:
                    transform.setRotate(90); transform.postScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_90: transform.setRotate(90); break;
                case ExifInterface.ORIENTATION_TRANSVERSE:
                    transform.setRotate(270); transform.postScale(-1, 1); break;
                case ExifInterface.ORIENTATION_ROTATE_270: transform.setRotate(270); break;
            }
            if (!transform.isIdentity()) {
                Bitmap rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(),
                        bitmap.getHeight(), transform, true);
                if (rotated != bitmap) {
                    bitmap.recycle();
                    bitmap = rotated;
                }
            }
            if (bitmap.hasAlpha()) {
                Bitmap opaque = Bitmap.createBitmap(bitmap.getWidth(), bitmap.getHeight(),
                        Bitmap.Config.ARGB_8888);
                Canvas canvas = new Canvas(opaque);
                canvas.drawColor(Color.WHITE);
                canvas.drawBitmap(bitmap, 0, 0, null);
                bitmap.recycle();
                bitmap = opaque;
            }
            try (ByteArrayOutputStream output = new ByteArrayOutputStream(SOFT_BYTES)) {
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 86, output)) {
                    throw new IOException("JPEG encoding failed");
                }
                return output.toByteArray();
            }
        } finally {
            bitmap.recycle();
        }
    }
}
