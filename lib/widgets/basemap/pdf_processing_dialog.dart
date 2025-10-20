import 'package:flutter/material.dart';
import '../../models/basemap_model.dart';
import '../../theme/app_theme.dart';

class PdfProcessingDialog extends StatelessWidget {
  final Basemap basemap;

  const PdfProcessingDialog({
    Key? key,
    required this.basemap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final progress = basemap.processingProgress ?? 0.0;
    final message = basemap.processingMessage ?? 'Processing...';
    final isComplete = progress >= 1.0;
    final isFailed = progress < 0;

    return WillPopScope(
      onWillPop: () async => isComplete || isFailed,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              isFailed ? Icons.error_outline : 
              isComplete ? Icons.check_circle_outline : Icons.hourglass_empty,
              color: isFailed ? AppTheme.errorColor :
                     isComplete ? AppTheme.primaryGreen : Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isFailed ? 'Processing Failed' :
                isComplete ? 'Complete!' : 'Processing PDF',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              basemap.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacingLarge),
            
            if (!isFailed) ...[
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? AppTheme.primaryGreen : AppTheme.accentGreen,
                ),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            
            if (isFailed) ...[
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.errorColor,
                ),
              ),
            ],
            
            const SizedBox(height: AppTheme.spacingLarge),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isFailed ? AppTheme.errorColor : 
                       isComplete ? AppTheme.primaryGreen : 
                       Colors.orange).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isFailed ? AppTheme.errorColor :
                           isComplete ? AppTheme.darkGreen : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isFailed 
                          ? 'Please check your PDF and try again.'
                          : isComplete
                              ? 'Your basemap is ready to use!'
                              : 'Please wait while tiles are being generated. This may take a few minutes.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isFailed ? AppTheme.errorColor :
                               isComplete ? AppTheme.darkGreen : Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isComplete || isFailed)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(isFailed ? 'Close' : 'Done'),
            ),
        ],
      ),
    );
  }
}
