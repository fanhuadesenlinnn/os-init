package tui

import (
	"testing"

	"github.com/fanhuadesenlinnn/os-init/internal/modules"
)

func TestModeModelOnlyShowsOperationsSupportedByEverySelection(t *testing.T) {
	module := modules.Module{SupportedOperations: []modules.Operation{
		modules.OperationInstall, modules.OperationUpdate, modules.OperationUninstall,
	}}
	archCapability := modules.Module{SupportedOperations: []modules.Operation{
		modules.OperationInstall, modules.OperationUpdate,
	}}
	model := newModeModel(module, archCapability)
	if len(model.options) != 2 || model.options[0].mode != modeInstall || model.options[1].mode != modeUpdate {
		t.Fatalf("filtered mode options = %#v", model.options)
	}

	action := modules.Module{SupportedOperations: []modules.Operation{modules.OperationInstall}}
	model = newModeModel(action)
	if len(model.options) != 1 || model.options[0].mode != modeInstall {
		t.Fatalf("action mode options = %#v", model.options)
	}
}
