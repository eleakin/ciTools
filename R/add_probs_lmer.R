# Copyright (C) 2017 Institute for Defense Analyses
#
# This file is part of ciTools.
#
# ciTools is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ciTools is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ciTools. If not, see <http://www.gnu.org/licenses/>.

#' Response Probabilities for Linear Mixed Models
#'
#' This function is one of the methods for \code{add_probs}, and is
#' called automatically when \code{add_probs} is used on a \code{fit}
#' of class \code{lmerMod}. 
#'
#' It is recommended that one perform a parametric bootstrap to
#' determine these probabilities. To do so, use the option \code{type = "boot"}
#'
#' @param tb A tibble or Data Frame.
#' @param fit An object of class \code{lmerMod}.
#' @param name NULL or character vector of length two. If \code{NULL},
#'     probabilities will automatically be named by \code{add_pi},
#'     otherwise, the probabilities will be named \code{name} in the
#'     returned tibble.
#' @param q A double. A quantile of the response variable
#' @param type A string, either \code{"parametric"} , \code{"sim"}, or
#'     \code{"boot"}.
#' @param includeRanef A logical. Set whether the predictions and
#'     intervals should be made conditional on the random effects. If
#'     \code{FALSE}, random effects will not be included.
#' @param nSims A positive integer. If \code{type = "sim"}
#'     \code{nSims} will determine the number of simulated draws to
#'     make.
#' @param comparison A character vector of length one. Must be either
#'     \code{"<"} or \code{">"}. If \code{comparison = "<"}, then
#'     \eqn{Pr(Y|x < q)} is calculated for each x in the new data,
#'     \code{tb}. Otherwise, \eqn{Pr(Y|x > q)} is calculated.
#' @param log_response A logical. Set to \code{TRUE} if your model is
#'     a log-linear mixed model.
#' @param yhatName A string. Determines the name of the vector of
#'     predictions.
#' @param ... Additional arguments.
#' 
#' @return A tibble, \code{tb}, with predictions and probabilities
#'     attached.
#'
#' @seealso \code{{\link{add_ci.lmerMod}}} for confidence intervals
#'     for \code{lmerMod} objects. \code{\link{add_pi.lmerMod}} for
#'     prediction intervals of \code{lmerMod} objects, and
#'     \code{\link{add_quantile.lmerMod}} for response quantiles of
#'     \code{lmerMod} objects.
#'
#' @examples
#' dat <- lme4::sleepstudy
#' fit <- lme4::lmer(Reaction ~ Days + (1|Subject), data = lme4::sleepstudy)
#' add_probs(dat, fit, q = 300)
#' add_probs(dat, fit, q = 300, type = "parametric", includeRanef = FALSE, comparison = ">")
#' add_probs(dat, fit, q = 300, type = "sim")
#' 
#' @export


add_probs.lmerMod <- function(tb, fit, 
                              q, name = NULL, comparison = "<", type = "parametric",
                              includeRanef = TRUE,
                              nSims = 200, log_response = FALSE, yhatName = "pred", ...) {
  
    if (is.null(name) && comparison == "<")
        name <- paste("prob_less_than", q, sep="")
    if (is.null(name) && comparison == ">")
        name <- paste("prob_greater_than", q, sep="")

    if (log_response)
        q <- log(q)

    if ((name %in% colnames(tb))) {
        warning ("These Probabilities may have already been appended to your dataframe. Overwriting.")
    }

    if (type == "parametric") 
        parametric_probs_mermod(tb, fit, q, name, includeRanef, comparison, yhatName)
    else if (type == "sim") 
        sim_probs_mermod(tb, fit, q, name, includeRanef, comparison, nSims, yhatName)
    else if (type == "boot")
        boot_probs_mermod(tb, fit, q, name, includeRanef, comparison, nSims, yhatName)
    else  
        stop("Incorrect type specified!")
    
}

parametric_probs_mermod <- function(tb, fit, q, name, includeRanef, comparison, yhatName){
    
    rdf <- get_resid_df_mermod(fit)
    seGlobal <- get_pi_mermod_var(tb, fit, includeRanef)
    
    if(includeRanef)
        re.form <- NULL
    else
        re.form <- NA

    out <- predict(fit, tb, re.form = re.form)
    if(is.null(tb[[yhatName]]))
        tb[[yhatName]] <- out
    
    t_quantile <- (q - out) / seGlobal

    if (comparison == "<")
        t_prob <- pt(q = t_quantile, df = rdf)
    if (comparison == ">")
        t_prob <- 1 - pt(q = t_quantile, df = rdf)

    tb[[name]] <- t_prob
    tibble::as_data_frame(tb)
}


sim_probs_mermod <- function(tb, fit, q, name, includeRanef, comparison, nSims = 200, yhatName) {

    if (includeRanef) {
        which <-  "full"
        re.form <- NULL
    } else {
        which <- "fixed"
        re.form <- NA
    }

    pi_out <- suppressWarnings(predictInterval(fit, tb, which = which, level = 0.95,
                              n.sims = nSims,
                              stat = "median",
                              include.resid.var = TRUE,
                              returnSims = TRUE))
    
    store_sim <- attributes(pi_out)$sim.results
    probs <- apply(store_sim, 1, FUN = calc_prob, quant = q, comparison = comparison)

    if(is.null(tb[[yhatName]]))
        tb[[yhatName]] <- predict(fit, tb, re.form = re.form)
    tb[[name]] <- probs
    tibble::as_data_frame(tb)
    
}

boot_probs_mermod <- function(tb, fit, q, name, includeRanef, comparison, nSims, yhatName){

    if (includeRanef) 
        reform = NULL
    else 
        reform = NA

    gg <- simulate(fit, re.form = reform, nsim = nSims)
    gg <- as.matrix(gg)
    probs <- apply(gg, 1, FUN = calc_prob, quant = q, comparison = comparison)

    if(is.null(tb[[yhatName]]))
        tb[[yhatName]] <- predict(fit, tb, re.form = reform)
    tb[[name]] <- probs
    tibble::as_data_frame(tb)

}