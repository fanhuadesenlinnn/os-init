package planner

import (
	"sort"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

type Options struct {
	Operation modules.Operation
}

type Plan struct {
	Modules           []modules.Module
	AddedDependencies []DependencyAddition
	SoftAssociations  []SoftAssociation
	Issues            []Issue
}

type DependencyAddition struct {
	ModuleID        string
	Label           string
	RequiredByID    string
	RequiredByLabel string
}

type SoftAssociation struct {
	ModuleID       string
	Label          string
	SuggestedID    string
	SuggestedLabel string
	ReasonZH       string
	ReasonEN       string
}

type Issue struct {
	Blocking  bool
	MessageZH string
	MessageEN string
	ModuleIDs []string
}

func (p Plan) BlockingIssue() (Issue, bool) {
	for _, issue := range p.Issues {
		if issue.Blocking {
			return issue, true
		}
	}
	return Issue{}, false
}

func Build(selected []modules.Module, target platform.Target, opts Options) Plan {
	operation := opts.Operation
	if operation == "" {
		operation = modules.OperationInstall
	}

	selected = dedupeModules(selected)
	plan := Plan{Modules: selected}
	if len(selected) == 0 {
		return plan
	}

	available, registryOrder := availableModules(target, selected)
	validateSelection(selected, operation, &plan)
	if _, blocked := plan.BlockingIssue(); blocked {
		return plan
	}
	planned := append([]modules.Module(nil), selected...)
	plannedByID := map[string]modules.Module{}
	for _, m := range planned {
		plannedByID[m.ID] = m
	}

	if operation != modules.OperationUninstall {
		visiting := map[string]bool{}
		for i := 0; i < len(planned); i++ {
			ensureDependencies(planned[i], available, plannedByID, &planned, &plan, visiting)
		}
		plan.SoftAssociations = softAssociations(plannedByID, available)
	}

	planned = executableModules(planned)
	ordered, cycle := orderModules(planned, registryOrder)
	if len(cycle) > 0 {
		plan.Modules = planned
		plan.Issues = append(plan.Issues, Issue{
			Blocking:  true,
			MessageZH: "模块依赖存在循环，无法生成可靠执行计划。",
			MessageEN: "The module dependency graph contains a cycle, so a reliable execution plan cannot be built.",
			ModuleIDs: cycle,
		})
		return plan
	}
	if operation == modules.OperationUninstall {
		reverseModules(ordered)
	}
	plan.Modules = ordered
	return plan
}

func validateSelection(selected []modules.Module, operation modules.Operation, plan *Plan) {
	actions := 0
	stateful := 0
	for _, module := range selected {
		if module.EntryKind == modules.EntryAction {
			actions++
		} else {
			stateful++
		}
		if !module.SupportsOperation(operation) {
			plan.Issues = append(plan.Issues, Issue{
				Blocking:  true,
				MessageZH: "选中的项目不支持当前操作：" + module.Label,
				MessageEN: "The selected item does not support this operation: " + module.Label,
				ModuleIDs: []string{module.ID},
			})
		}
	}
	if actions > 0 && stateful > 0 {
		plan.Issues = append(plan.Issues, Issue{
			Blocking:  true,
			MessageZH: "诊断/状态操作不能与安装模块在同一批次执行。",
			MessageEN: "Diagnostic/status actions cannot be mixed with lifecycle modules in one batch.",
		})
	}
}

func executableModules(planned []modules.Module) []modules.Module {
	out := make([]modules.Module, 0, len(planned))
	for _, module := range planned {
		if module.EntryKind != modules.EntryPreset {
			out = append(out, module)
		}
	}
	return out
}

func ensureDependencies(
	m modules.Module,
	available map[string]modules.Module,
	plannedByID map[string]modules.Module,
	planned *[]modules.Module,
	plan *Plan,
	visiting map[string]bool,
) {
	if visiting[m.ID] {
		return
	}
	visiting[m.ID] = true
	defer delete(visiting, m.ID)

	for _, depID := range m.DependsOn {
		if dep, ok := plannedByID[depID]; ok {
			ensureDependencies(dep, available, plannedByID, planned, plan, visiting)
			continue
		}

		dep, ok := available[depID]
		if !ok {
			plan.Issues = append(plan.Issues, Issue{
				Blocking:  true,
				MessageZH: "选中的模块依赖当前系统不可用的模块，无法生成可靠执行计划。",
				MessageEN: "A selected module depends on a module that is unavailable on this system, so a reliable execution plan cannot be built.",
				ModuleIDs: []string{m.ID, depID},
			})
			continue
		}

		plannedByID[dep.ID] = dep
		*planned = append(*planned, dep)
		plan.AddedDependencies = append(plan.AddedDependencies, DependencyAddition{
			ModuleID:        dep.ID,
			Label:           dep.Label,
			RequiredByID:    m.ID,
			RequiredByLabel: m.Label,
		})
		ensureDependencies(dep, available, plannedByID, planned, plan, visiting)
	}
}

func softAssociations(plannedByID, available map[string]modules.Module) []SoftAssociation {
	rules := []struct {
		sourceID    string
		suggestedID string
		reasonZH    string
		reasonEN    string
	}{
		{
			sourceID:    "docker",
			suggestedID: "network-tune",
			reasonZH:    "容器和反向代理场景通常会受益于队列、ring buffer 和 MSS 基线优化。",
			reasonEN:    "Container and reverse-proxy hosts often benefit from queue, ring buffer, and MSS baseline tuning.",
		},
	}

	var out []SoftAssociation
	for _, rule := range rules {
		source, hasSource := plannedByID[rule.sourceID]
		if !hasSource {
			continue
		}
		if _, alreadyPlanned := plannedByID[rule.suggestedID]; alreadyPlanned {
			continue
		}
		suggested, ok := available[rule.suggestedID]
		if !ok {
			continue
		}
		out = append(out, SoftAssociation{
			ModuleID:       source.ID,
			Label:          source.Label,
			SuggestedID:    suggested.ID,
			SuggestedLabel: suggested.Label,
			ReasonZH:       rule.reasonZH,
			ReasonEN:       rule.reasonEN,
		})
	}
	return out
}

func orderModules(planned []modules.Module, registryOrder map[string]int) ([]modules.Module, []string) {
	if len(planned) < 2 {
		return planned, nil
	}

	byID := map[string]modules.Module{}
	deps := map[string]map[string]bool{}
	for _, m := range planned {
		byID[m.ID] = m
		deps[m.ID] = map[string]bool{}
	}
	for _, m := range planned {
		for _, depID := range m.DependsOn {
			if _, ok := byID[depID]; ok {
				deps[m.ID][depID] = true
			}
		}
	}

	remaining := map[string]bool{}
	for _, m := range planned {
		remaining[m.ID] = true
	}

	ordered := make([]modules.Module, 0, len(planned))
	for len(remaining) > 0 {
		candidates := make([]modules.Module, 0, len(remaining))
		for id := range remaining {
			if len(deps[id]) == 0 {
				candidates = append(candidates, byID[id])
			}
		}
		if len(candidates) == 0 {
			cycle := make([]string, 0, len(remaining))
			for id := range remaining {
				cycle = append(cycle, id)
			}
			sort.Strings(cycle)
			return nil, cycle
		}

		sort.SliceStable(candidates, func(i, j int) bool {
			return moduleLess(candidates[i], candidates[j], registryOrder)
		})

		next := candidates[0]
		ordered = append(ordered, next)
		delete(remaining, next.ID)
		for id := range deps {
			delete(deps[id], next.ID)
		}
	}

	return ordered, nil
}

func reverseModules(items []modules.Module) {
	for left, right := 0, len(items)-1; left < right; left, right = left+1, right-1 {
		items[left], items[right] = items[right], items[left]
	}
}

func moduleLess(a, b modules.Module, registryOrder map[string]int) bool {
	if ra, rb := moduleRank(a), moduleRank(b); ra != rb {
		return ra < rb
	}
	oa, oka := registryOrder[a.ID]
	ob, okb := registryOrder[b.ID]
	if oka && okb && oa != ob {
		return oa < ob
	}
	if oka != okb {
		return oka
	}
	return a.ID < b.ID
}

func moduleRank(m modules.Module) int {
	return int(m.Phase)*1000 + m.Order
}

func availableModules(target platform.Target, selected []modules.Module) (map[string]modules.Module, map[string]int) {
	available := map[string]modules.Module{}
	registryOrder := map[string]int{}
	for i, m := range modules.ForTarget(target) {
		available[m.ID] = m
		registryOrder[m.ID] = i
	}
	for _, m := range selected {
		if _, ok := available[m.ID]; !ok {
			available[m.ID] = m
			registryOrder[m.ID] = len(registryOrder)
		}
	}
	return available, registryOrder
}

func dedupeModules(selected []modules.Module) []modules.Module {
	seen := map[string]bool{}
	out := make([]modules.Module, 0, len(selected))
	for _, m := range selected {
		if m.ID == "" || seen[m.ID] {
			continue
		}
		seen[m.ID] = true
		out = append(out, m)
	}
	return out
}
