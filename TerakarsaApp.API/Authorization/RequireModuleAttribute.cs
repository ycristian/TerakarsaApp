using System.Linq;
using Microsoft.AspNetCore.Mvc.Filters;

namespace TerakarsaApp.API.Authorization;

// Boleh diisi lebih dari satu kode (OR) -- dipakai controller yang bisa diakses lewat
// lebih dari satu module, mis. WorkflowLogController lewat ORDER_PROJECT atau WORKFLOW_INPUT.
public class RequireModuleAttribute : Attribute, IAuthorizationFilter
{
    private readonly string[] _moduleCodes;

    public RequireModuleAttribute(params string[] moduleCodes)
    {
        _moduleCodes = moduleCodes;
    }

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        if (!_moduleCodes.Any(code => context.HttpContext.User.HasClaim("module", code)))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.ForbidResult();
        }
    }
}
