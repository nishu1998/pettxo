package com.pettexo.app

import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.yalantis.ucrop.UCropActivity

/** Keeps uCrop's native editing controls clear of the Android navigation bar. */
class PettxoUCropActivity : UCropActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val cropperRoot = findViewById<View>(R.id.ucrop_photobox)
        val controlsWrapper = findViewById<View>(R.id.controls_wrapper)
        val originalLayoutParams =
            controlsWrapper.layoutParams as? ViewGroup.MarginLayoutParams ?: return
        val originalBottomMargin = originalLayoutParams.bottomMargin

        ViewCompat.setOnApplyWindowInsetsListener(cropperRoot) { _, windowInsets ->
            val navigationBarBottom =
                windowInsets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom
            val layoutParams = controlsWrapper.layoutParams as ViewGroup.MarginLayoutParams
            val insetBottomMargin = originalBottomMargin + navigationBarBottom

            if (layoutParams.bottomMargin != insetBottomMargin) {
                layoutParams.bottomMargin = insetBottomMargin
                controlsWrapper.layoutParams = layoutParams
            }

            windowInsets
        }
        ViewCompat.requestApplyInsets(cropperRoot)
    }
}
