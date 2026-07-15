package modules

import "fmt"

// ValidateCatalog validates extension-facing invariants independently from
// platform filtering and execution planning.
func ValidateCatalog(entries []Module) []error {
	var issues []error
	allowedRequirements := map[string]bool{
		"linux": true, "systemd": true, "native-linux": true,
		"native-or-wsl2": true, "wsl": true, "wsl2": true, "wslg": true,
	}
	byID := make(map[string]Module, len(entries))
	for _, entry := range entries {
		if entry.ID == "" {
			issues = append(issues, fmt.Errorf("catalog entry has an empty ID"))
			continue
		}
		if _, exists := byID[entry.ID]; exists {
			issues = append(issues, fmt.Errorf("duplicate catalog ID: %s", entry.ID))
		}
		byID[entry.ID] = entry
		if entry.EntryKind != EntryPreset && entry.Script == "" {
			issues = append(issues, fmt.Errorf("entry %s has no provider script", entry.ID))
		}
		if len(entry.SupportedOperations) == 0 {
			issues = append(issues, fmt.Errorf("entry %s has no declared lifecycle", entry.ID))
		}
		for _, requirement := range entry.Requires {
			if !allowedRequirements[requirement] {
				issues = append(issues, fmt.Errorf("entry %s has unknown requirement %s", entry.ID, requirement))
			}
		}
		if entry.EntryKind == EntryModule && entry.Delivery.Default == "" {
			issues = append(issues, fmt.Errorf("entry %s has no declared delivery policy", entry.ID))
		}
		seenOperations := map[Operation]bool{}
		for _, operation := range entry.SupportedOperations {
			if operation != OperationInstall && operation != OperationUpdate && operation != OperationUninstall {
				issues = append(issues, fmt.Errorf("entry %s has unknown operation %s", entry.ID, operation))
			}
			if seenOperations[operation] {
				issues = append(issues, fmt.Errorf("entry %s repeats operation %s", entry.ID, operation))
			}
			seenOperations[operation] = true
		}
	}
	for _, entry := range entries {
		for _, dependency := range entry.DependsOn {
			if _, exists := byID[dependency]; !exists {
				issues = append(issues, fmt.Errorf("entry %s depends on unknown entry %s", entry.ID, dependency))
			}
		}
	}
	return issues
}
