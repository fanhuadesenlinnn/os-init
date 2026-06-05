package planner

import (
	"sort"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
	"github.com/fanhuadesenlinnn/os-init/internal/platform"
)

type Mode string

const (
	ModeInstall   Mode = "install"
	ModeUpdate    Mode = "update"
	ModeUninstall Mode = "uninstall"
)

type Options struct {
	Mode Mode
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
	mode := opts.Mode
	if mode == "" {
		mode = ModeInstall
	}

	selected = dedupeModules(selected)
	plan := Plan{Modules: selected}
	if len(selected) == 0 {
		return plan
	}

	if archDevKitCount(selected) > 0 && len(selected) > 1 {
		plan.Issues = append(plan.Issues, Issue{
			Blocking:  true,
			MessageZH: "ArchDevKit 是独立初始化流程，一次只能执行一个 ArchDevKit 动作，不能和普通模块混在同一批次。",
			MessageEN: "ArchDevKit is an independent initialization flow. Run exactly one ArchDevKit action at a time and do not mix it with normal modules.",
			ModuleIDs: moduleIDs(selected),
		})
		return plan
	}

	available, registryOrder := availableModules(target, selected)
	planned := append([]modules.Module(nil), selected...)
	plannedByID := map[string]modules.Module{}
	for _, m := range planned {
		plannedByID[m.ID] = m
	}

	if mode != ModeUninstall {
		visiting := map[string]bool{}
		for i := 0; i < len(planned); i++ {
			ensureDependencies(planned[i], available, plannedByID, &planned, &plan, visiting)
		}
		plan.SoftAssociations = softAssociations(plannedByID, available)
	}

	plan.Modules = orderModules(planned, registryOrder)
	return plan
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

func orderModules(planned []modules.Module, registryOrder map[string]int) []modules.Module {
	if len(planned) < 2 {
		return planned
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
			for id := range remaining {
				candidates = append(candidates, byID[id])
			}
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

	return ordered
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
	if m.Category == "archdevkit" {
		return 0
	}
	if m.Category == "optimization" {
		switch m.ID {
		case "network-ipv4":
			return 80
		case "network-tune":
			return 81
		default:
			return 82
		}
	}
	if m.Category != "installation" {
		return 100
	}

	switch m.Subsection {
	case "Shell 工具":
		return shellRank(m.ID)
	case "终端体验":
		return 19
	case "终端工具":
		return 20
	case "macOS 命令行":
		return 25
	case "网络代理":
		return 30
	case "开发工具":
		switch m.ID {
		case "go":
			return 40
		case "neovim":
			return 45
		case "docker":
			return 50
		default:
			return 45
		}
	case "macOS 开发应用":
		return 60
	case "macOS 代理网络":
		return 61
	case "macOS 效率工具":
		return 62
	case "macOS 输入增强":
		return 63
	case "macOS 媒体下载":
		return 64
	case "macOS AI 笔记":
		return 65
	case "macOS 通讯办公":
		return 66
	case "macOS 字体":
		return 67
	default:
		return 70
	}
}

func shellRank(id string) int {
	switch id {
	case "shell-zsh":
		return 10
	case "shell-git":
		return 11
	case "shell-starship":
		return 12
	case "shell-direnv":
		return 13
	case "shell-autosuggestions":
		return 14
	case "shell-syntax-hl":
		return 15
	case "shell-nvm":
		return 16
	case "shell-fnm":
		return 17
	case "shell-byobu":
		return 18
	default:
		return 19
	}
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

func archDevKitCount(selected []modules.Module) int {
	count := 0
	for _, m := range selected {
		if m.Category == "archdevkit" {
			count++
		}
	}
	return count
}

func moduleIDs(selected []modules.Module) []string {
	ids := make([]string, 0, len(selected))
	for _, m := range selected {
		ids = append(ids, m.ID)
	}
	return ids
}
