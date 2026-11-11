import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np

# Define the confusion matrix
cm = np.array([
    [0.75, 0.00, 0.02, 0.04, 0.01, 0.04, 0.10, 0.01, 0.02, 0.01],
    [0.00, 0.91, 0.03, 0.03, 0.00, 0.01, 0.01, 0.00, 0.01, 0.00],
    [0.03, 0.07, 0.44, 0.12, 0.03, 0.05, 0.18, 0.02, 0.05, 0.01],
    [0.02, 0.06, 0.14, 0.45, 0.02, 0.10, 0.09, 0.02, 0.08, 0.03],
    [0.00, 0.05, 0.04, 0.02, 0.48, 0.03, 0.12, 0.08, 0.06, 0.11],
    [0.07, 0.06, 0.07, 0.19, 0.06, 0.18, 0.15, 0.04, 0.15, 0.05],
    [0.03, 0.02, 0.07, 0.03, 0.05, 0.02, 0.75, 0.00, 0.02, 0.01],
    [0.01, 0.09, 0.04, 0.04, 0.09, 0.02, 0.03, 0.56, 0.04, 0.09],
    [0.02, 0.11, 0.16, 0.18, 0.05, 0.07, 0.14, 0.05, 0.19, 0.05],
    [0.00, 0.08, 0.04, 0.03, 0.31, 0.02, 0.08, 0.19, 0.07, 0.18]
])

plt.figure(figsize=(10, 8))
sns.set_theme(style=white)

# Plot heatmap
ax = sns.heatmap(
    cm, 
    annot=True, 
    fmt=.2f, 
    cmap=Blues, 
    cbar=True,
    xticklabels=[str(i) for i in range(10)],
    yticklabels=[str(i) for i in range(10)],
    linewidths=0.5,
    linecolor='lightgrey',
    square=True
)

plt.title(Normalized Confusion Matrix, fontsize=14, pad=15, fontweight='bold')
plt.xlabel(Predicted Label, fontsize=12, labelpad=10)
plt.ylabel(True Label, fontsize=12, labelpad=10)
plt.tight_layout()

# Save image
plt.savefig(confusion_matrix.png, dpi=300)
plt.close()
print(Confusion matrix generated and saved successfully.)
