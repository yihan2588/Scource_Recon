# Active/Sham tagging plan

1. After `process_ft_sourcestatistics`, call `process_add_tag` with the desired label
   * Use `contextLabel` if available, otherwise fall back to group/stage pair.
   * Example tag: `ActiveStim_vs_Pre_Night1`.
2. Update run log to mention that the tag was applied.
3. Verify that the resulting Brainstorm stat file comment and filename include the tag.
