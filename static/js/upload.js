// ============================================================================
// The Markdown Redemption - Upload JavaScript
// ============================================================================

document.addEventListener('DOMContentLoaded', function() {
    const dropZone = document.getElementById('drop-zone');
    const fileInput = document.getElementById('file-input');
    const fileList = document.getElementById('file-list');
    const fileItems = document.getElementById('file-items');
    const fileCount = document.getElementById('file-count');
    const totalSize = document.getElementById('total-size');
    const submitBtn = document.getElementById('submit-btn');
    const clearAllBtn = document.getElementById('clear-all');
    const uploadForm = document.getElementById('upload-form');

    let selectedFiles = [];
    const maxFiles = parseInt(dropZone.dataset.maxFiles) || 100;
    const maxSizeMB = parseInt(dropZone.dataset.maxSizeMb) || 100;
    const maxSizeBytes = maxSizeMB * 1024 * 1024;
    const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'pdf'];

    // Click to browse
    dropZone.addEventListener('click', () => {
        fileInput.click();
    });

    // File input change
    fileInput.addEventListener('change', (e) => {
        handleFiles(e.target.files);
    });

    // Drag and drop events
    dropZone.addEventListener('dragover', (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.add('drag-over');
    });

    dropZone.addEventListener('dragleave', (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.remove('drag-over');
    });

    dropZone.addEventListener('drop', (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropZone.classList.remove('drag-over');
        
        const files = e.dataTransfer.files;
        handleFiles(files);
    });

    // Prevent default drag behaviors on document
    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
        document.body.addEventListener(eventName, (e) => {
            e.preventDefault();
            e.stopPropagation();
        }, false);
    });

    // Handle files
    function handleFiles(files) {
        const filesArray = Array.from(files);
        
        // Validate file count
        if (selectedFiles.length + filesArray.length > maxFiles) {
            showFlashMessage('Maximum ' + maxFiles + ' files allowed', 'error');
            return;
        }

        filesArray.forEach(file => {
            // Validate extension
            const ext = file.name.split('.').pop().toLowerCase();
            if (!allowedExtensions.includes(ext)) {
                showFlashMessage('File type not allowed: ' + file.name, 'warning');
                return;
            }

            // Validate size
            if (file.size > maxSizeBytes) {
                showFlashMessage('File exceeds ' + maxSizeMB + 'MB limit: ' + file.name, 'error');
                return;
            }

            // Check for duplicates (by name and size)
            const isDuplicate = selectedFiles.some(f => 
                f.name === file.name && f.size === file.size
            );
            if (isDuplicate) {
                showFlashMessage('File already added: ' + file.name, 'warning');
                return;
            }

            selectedFiles.push(file);
        });

        updateFileList();
        updateSubmitButton();
    }

    // Update file list display
    function updateFileList() {
        if (selectedFiles.length === 0) {
            fileList.style.display = 'none';
            return;
        }

        fileList.style.display = 'block';
        fileCount.textContent = selectedFiles.length;

        // Clear existing items
        fileItems.innerHTML = '';

        // Add file items
        selectedFiles.forEach((file, index) => {
            const fileItem = createFileItem(file, index);
            fileItems.appendChild(fileItem);
        });

        // Update total size
        const total = selectedFiles.reduce((sum, file) => sum + file.size, 0);
        totalSize.textContent = 'Total: ' + formatFileSize(total);
    }

    // Create file item element
    function createFileItem(file, index) {
        const item = document.createElement('div');
        item.className = 'file-item';

        const ext = file.name.split('.').pop().toLowerCase();
        const isPDF = ext === 'pdf';

        const pdfIcon = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><text x="12" y="17" text-anchor="middle" font-size="6" fill="currentColor">PDF</text></svg>';
        const imageIcon = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>';

        item.innerHTML = '<div class="file-info"><div class="file-icon">' + 
            (isPDF ? pdfIcon : imageIcon) + 
            '</div><span class="file-name">' + escapeHtml(file.name) + '</span></div>' +
            '<span class="file-size">' + formatFileSize(file.size) + '</span>' +
            '<button type="button" class="remove-file" data-index="' + index + '" title="Remove file">✕</button>';

        // Add remove handler
        const removeBtn = item.querySelector('.remove-file');
        removeBtn.addEventListener('click', () => {
            removeFile(index);
        });

        return item;
    }

    // Remove file
    function removeFile(index) {
        selectedFiles.splice(index, 1);
        updateFileList();
        updateSubmitButton();
    }

    // Clear all files
    clearAllBtn.addEventListener('click', () => {
        selectedFiles = [];
        fileInput.value = '';
        updateFileList();
        updateSubmitButton();
    });

    // Update submit button state
    function updateSubmitButton() {
        submitBtn.disabled = selectedFiles.length === 0;
    }

    // Form submission
    uploadForm.addEventListener('submit', (e) => {
        if (selectedFiles.length === 0) {
            e.preventDefault();
            showFlashMessage('Please select at least one file', 'error');
            return;
        }

        // Create new FileList from selected files
        const dataTransfer = new DataTransfer();
        selectedFiles.forEach(file => {
            dataTransfer.items.add(file);
        });
        fileInput.files = dataTransfer.files;

        // Hide file list and submit button
        fileList.style.display = 'none';
        submitBtn.style.display = 'none';

        // Show processing indicator
        const processingIndicator = document.getElementById('processing-indicator');
        if (processingIndicator) {
            processingIndicator.style.display = 'block';
        }

        // Show current file being processed
        const currentFileEl = document.getElementById('current-file');
        const currentFilenameEl = document.getElementById('current-filename');
        if (currentFileEl && currentFilenameEl && selectedFiles.length > 0) {
            currentFileEl.style.display = 'block';
            currentFilenameEl.textContent = selectedFiles[0].name;
        }

        // Add animations
        const style = document.createElement('style');
        style.textContent = `
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            @keyframes dots {
                0%, 20% { opacity: 0; }
                50% { opacity: 1; }
                100% { opacity: 0; }
            }
            @keyframes fadeIn {
                from { opacity: 0; transform: translateY(10px); }
                to { opacity: 1; transform: translateY(0); }
            }
            .processing-spinner svg {
                animation: spin 0.8s linear infinite;
            }
            .processing-indicator {
                animation: fadeIn 0.3s ease-out;
            }
            .processing-dots span:nth-child(1) { animation: dots 1.4s infinite; animation-delay: 0s; }
            .processing-dots span:nth-child(2) { animation: dots 1.4s infinite; animation-delay: 0.2s; }
            .processing-dots span:nth-child(3) { animation: dots 1.4s infinite; animation-delay: 0.4s; }
        `;
        document.head.appendChild(style);
    });

    // Utility: Format file size
    function formatFileSize(bytes) {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    // Utility: Escape HTML
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // Utility: Show flash message
    function showFlashMessage(message, type) {
        type = type || 'info';
        const flashContainer = document.querySelector('.flash-messages') || createFlashContainer();
        
        const flashMessage = document.createElement('div');
        flashMessage.className = 'flash-message flash-' + type;
        
        const icon = type === 'error' ? '⚠' : type === 'success' ? '✓' : type === 'warning' ? '⚡' : 'ℹ';
        
        flashMessage.innerHTML = '<span class="flash-icon">' + icon + '</span><span class="flash-text">' + escapeHtml(message) + '</span>';
        
        flashContainer.appendChild(flashMessage);
        
        // Auto-remove after 5 seconds
        setTimeout(() => {
            flashMessage.style.transition = 'opacity 0.3s';
            flashMessage.style.opacity = '0';
            setTimeout(() => flashMessage.remove(), 300);
        }, 5000);
    }

    // Create flash container if it doesn't exist
    function createFlashContainer() {
        const container = document.createElement('div');
        container.className = 'flash-messages';
        const mainContent = document.querySelector('.main-content .container');
        mainContent.insertBefore(container, mainContent.firstChild);
        return container;
    }
});
